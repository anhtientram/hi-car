package flutter.overlay.window.flutter_overlay_window;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.res.Configuration;
import android.content.res.Resources;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.app.PendingIntent;
import android.graphics.Point;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.util.DisplayMetrics;
import android.util.Log;
import android.util.TypedValue;
import android.view.Display;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;

import androidx.annotation.Nullable;
import androidx.annotation.RequiresApi;
import androidx.core.app.NotificationCompat;

import java.util.HashMap;
import java.util.Map;
import java.util.Timer;
import java.util.TimerTask;

import io.flutter.embedding.android.FlutterTextureView;
import io.flutter.embedding.android.FlutterView;
import io.flutter.FlutterInjector;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngineCache;
import io.flutter.embedding.engine.FlutterEngineGroup;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.plugin.common.BasicMessageChannel;
import io.flutter.plugin.common.JSONMessageCodec;
import io.flutter.plugin.common.MethodChannel;

public class OverlayService extends Service implements View.OnTouchListener {
    private final int DEFAULT_NAV_BAR_HEIGHT_DP = 48;
    private final int DEFAULT_STATUS_BAR_HEIGHT_DP = 25;

    private Integer mStatusBarHeight = -1;
    private Integer mNavigationBarHeight = -1;
    private Resources mResources;

    public static final String INTENT_EXTRA_IS_CLOSE_WINDOW = "IsCloseWindow";

    private static OverlayService instance;
    public static boolean isRunning = false;
    private WindowManager windowManager = null;
    private FlutterView flutterView;
    private MethodChannel flutterChannel;
    private BasicMessageChannel<Object> overlayMessageChannel;
    private int clickableFlag = WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE | WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE |
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN;

    private Handler mAnimationHandler = new Handler();
    private float lastX, lastY;
    private float touchDownRawX, touchDownRawY;
    private int lastYPosition;
    private boolean dragging;
    private boolean initialPositionApplied;
    private int pendingStartX = OverlayConstants.DEFAULT_XY;
    private int pendingStartY = OverlayConstants.DEFAULT_XY;
    private static final float DRAG_SLOP_DP = 10f;
    // Bi?n k?o cache l?c ACTION_DOWN ? tr?nh ?o m?n h?nh m?i frame.
    private int dragMinX, dragMinY, dragMaxX, dragMaxY;
    private static final float MAXIMUM_OPACITY_ALLOWED_FOR_S_AND_HIGHER = 0.8f;
    private Point szWindow = new Point();
    private Timer mTrayAnimationTimer;
    private TrayAnimationTimerTask mTrayTimerTask;

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @RequiresApi(api = Build.VERSION_CODES.M)
    @Override
    public void onDestroy() {
        Log.d("OverLay", "Destroying the overlay window service");
        if (windowManager != null) {
            try { windowManager.removeView(flutterView); }
            catch (Exception e) { diagnosticError("overlay_remove_view", e); }
            windowManager = null;
            if (flutterView != null) flutterView.detachFromFlutterEngine();
            flutterView = null;
        }
        mAnimationHandler.removeCallbacksAndMessages(null);
        if (mTrayAnimationTimer != null) mTrayAnimationTimer.cancel();
        isRunning = false;
        NotificationManager notificationManager = (NotificationManager) getApplicationContext().getSystemService(Context.NOTIFICATION_SERVICE);
        notificationManager.cancel(OverlayConstants.NOTIFICATION_ID);
        instance = null;
        super.onDestroy();
    }

    @RequiresApi(api = Build.VERSION_CODES.JELLY_BEAN_MR1)
    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        mResources = getApplicationContext().getResources();
        // START_STICKY delivers a null intent after process death.
        int startX = intent == null ? OverlayConstants.DEFAULT_XY : intent.getIntExtra("startX", OverlayConstants.DEFAULT_XY);
        int startY = intent == null ? OverlayConstants.DEFAULT_XY : intent.getIntExtra("startY", OverlayConstants.DEFAULT_XY);
        android.content.SharedPreferences prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE);
        boolean allowed = "android_screen_mode".equals(prefs.getString("flutter.connection_mode", ""))
                && prefs.getBoolean("flutter.is_bubble_enabled", true)
                && !prefs.getString("flutter.auth_token", "").isEmpty()
                && (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || android.provider.Settings.canDrawOverlays(this));
        boolean isCloseWindow = !allowed || (intent != null && intent.getBooleanExtra(INTENT_EXTRA_IS_CLOSE_WINDOW, false));
        if (isCloseWindow) {
            if (windowManager != null) {
                try { windowManager.removeView(flutterView); }
                catch (Exception e) { diagnosticError("overlay_close_view", e); }
                windowManager = null;
                flutterView.detachFromFlutterEngine();
            }
            isRunning = false;
            stopSelf();
            return START_NOT_STICKY;
        }
        if (windowManager != null) {
            try { windowManager.removeView(flutterView); }
            catch (Exception e) { diagnosticError("overlay_replace_view", e); }
            windowManager = null;
            flutterView.detachFromFlutterEngine();
        }
        isRunning = true;
        Log.d("onStartCommand", "Service started");
        initialPositionApplied = false;
        pendingStartX = startX;
        pendingStartY = startY;
        FlutterEngine engine = FlutterEngineCache.getInstance().get(OverlayConstants.CACHED_TAG);
        engine.getLifecycleChannel().appIsResumed();
        flutterView = new FlutterView(getApplicationContext(), new FlutterTextureView(getApplicationContext()));
        flutterView.attachToFlutterEngine(FlutterEngineCache.getInstance().get(OverlayConstants.CACHED_TAG));
        registerOverlayBridge(engine);
        flutterView.setFitsSystemWindows(true);
        flutterView.setFocusable(true);
        flutterView.setFocusableInTouchMode(true);
        flutterView.setBackgroundColor(Color.TRANSPARENT);
        flutterChannel.setMethodCallHandler((call, result) -> {
            if (call.method.equals("updateFlag")) {
                String flag = call.argument("flag").toString();
                updateOverlayFlag(result, flag);
            } else if (call.method.equals("updateOverlayPosition")) {
                int x = call.<Integer>argument("x");
                int y = call.<Integer>argument("y");
                moveOverlay(x, y, result);
            } else if (call.method.equals("resizeOverlay")) {
                int width = call.argument("width");
                int height = call.argument("height");
                boolean enableDrag = call.argument("enableDrag");
                resizeOverlay(width, height, enableDrag, result);
            }
        });
        overlayMessageChannel.setMessageHandler((message, reply) -> {
            WindowSetup.messenger.send(message);
        });
        windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
            windowManager.getDefaultDisplay().getSize(szWindow);
        } else {
            DisplayMetrics displaymetrics = new DisplayMetrics();
            windowManager.getDefaultDisplay().getMetrics(displaymetrics);
            int w = displaymetrics.widthPixels;
            int h = displaymetrics.heightPixels;
            szWindow.set(w, h);
        }
        WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                WindowSetup.width == -1999 ? -1 : WindowSetup.width,
                WindowSetup.height != -1999 ? WindowSetup.height : screenHeight(),
                0,
                0,
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY : WindowManager.LayoutParams.TYPE_PHONE,
                buildWindowFlags(),
                PixelFormat.TRANSLUCENT
        );
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && WindowSetup.flag == clickableFlag) {
            params.alpha = MAXIMUM_OPACITY_ALLOWED_FOR_S_AND_HIGHER;
        }
        params.gravity = WindowSetup.gravity;
        flutterView.setOnTouchListener(this);
        try {
            windowManager.addView(flutterView, params);
        } catch (Exception e) {
            diagnosticError("overlay_add_view", e);
            isRunning = false;
            stopSelf();
            return START_NOT_STICKY;
        }
        flutterView.post(this::applyInitialOverlayPosition);
        return START_STICKY;
    }

    /** ??t v? tr? ban ??u: m?c ??nh c?n gi?a d?c, s?t tr?i; clamp trong m?n h?nh. */
    private void applyInitialOverlayPosition() {
        if (flutterView == null || windowManager == null || initialPositionApplied) return;
        initialPositionApplied = true;

        WindowManager.LayoutParams lp = (WindowManager.LayoutParams) flutterView.getLayoutParams();
        refreshScreenSize();

        int viewWidth = overlayViewWidth(lp);
        int viewHeight = overlayViewHeight(lp);
        int edgeMargin = dpToPx(16);
        int topBound = statusBarHeightPx() + edgeMargin;
        int bottomBound = szWindow.y - (inPortrait() ? navigationBarHeightPx() : 0) - edgeMargin;
        int leftBound = edgeMargin;
        int rightBound = Math.max(leftBound, szWindow.x - edgeMargin);
        int maxLeft = Math.max(leftBound, rightBound - viewWidth);
        int maxTop = Math.max(topBound, bottomBound - viewHeight);

        int left = pendingStartX == OverlayConstants.DEFAULT_XY ? leftBound : dpToPx(pendingStartX);
        int top;
        if (pendingStartY == OverlayConstants.DEFAULT_XY) {
            top = topBound + Math.max(0, (bottomBound - topBound - viewHeight) / 2);
        } else {
            top = dpToPx(pendingStartY);
        }

        left = Math.max(leftBound, Math.min(left, maxLeft));
        top = Math.max(topBound, Math.min(top, maxTop));

        applyScreenPositionToParams(lp, left, top, viewWidth, viewHeight);
        windowManager.updateViewLayout(flutterView, lp);
    }


    @RequiresApi(api = Build.VERSION_CODES.JELLY_BEAN_MR1)
    private int screenHeight() {
        Display display = windowManager.getDefaultDisplay();
        DisplayMetrics dm = new DisplayMetrics();
        display.getRealMetrics(dm);
        return inPortrait() ?
                dm.heightPixels + statusBarHeightPx() + navigationBarHeightPx()
                :
                dm.heightPixels + statusBarHeightPx();
    }

    private int statusBarHeightPx() {
        if (mStatusBarHeight == -1) {
            int statusBarHeightId = mResources.getIdentifier("status_bar_height", "dimen", "android");

            if (statusBarHeightId > 0) {
                mStatusBarHeight = mResources.getDimensionPixelSize(statusBarHeightId);
            } else {
                mStatusBarHeight = dpToPx(DEFAULT_STATUS_BAR_HEIGHT_DP);
            }
        }

        return mStatusBarHeight;
    }

    int navigationBarHeightPx() {
        if (mNavigationBarHeight == -1) {
            int navBarHeightId = mResources.getIdentifier("navigation_bar_height", "dimen", "android");

            if (navBarHeightId > 0) {
                mNavigationBarHeight = mResources.getDimensionPixelSize(navBarHeightId);
            } else {
                mNavigationBarHeight = dpToPx(DEFAULT_NAV_BAR_HEIGHT_DP);
            }
        }

        return mNavigationBarHeight;
    }


    private void updateOverlayFlag(MethodChannel.Result result, String flag) {
        if (windowManager != null) {
            WindowSetup.setFlag(flag);
            WindowManager.LayoutParams params = (WindowManager.LayoutParams) flutterView.getLayoutParams();
            params.flags = buildWindowFlags();
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && WindowSetup.flag == clickableFlag) {
                params.alpha = MAXIMUM_OPACITY_ALLOWED_FOR_S_AND_HIGHER;
            } else {
                params.alpha = 1;
            }
            windowManager.updateViewLayout(flutterView, params);
            result.success(true);
        } else {
            result.success(false);
        }
    }

    private void resizeOverlay(int width, int height, boolean enableDrag, MethodChannel.Result result) {
        if (windowManager != null) {
            WindowManager.LayoutParams params = (WindowManager.LayoutParams) flutterView.getLayoutParams();
            params.width = (width == -1999 || width == -1) ? -1 : dpToPx(width);
            params.height = (height != 1999 || height != -1) ? dpToPx(height) : height;
            WindowSetup.enableDrag = enableDrag;
            params.flags = buildWindowFlags();
            clampOverlayPosition(params);
            windowManager.updateViewLayout(flutterView, params);
            result.success(true);
        } else {
            result.success(false);
        }
    }

    private void moveOverlay(int x, int y, MethodChannel.Result result) {
        if (windowManager != null) {
            WindowManager.LayoutParams params = (WindowManager.LayoutParams) flutterView.getLayoutParams();
            params.x = (x == -1999 || x == -1) ? -1 : dpToPx(x);
            params.y = dpToPx(y);
            clampOverlayPosition(params);
            windowManager.updateViewLayout(flutterView, params);
            if (result != null)
                result.success(true);
        } else {
            if (result != null)
                result.success(false);
        }
    }


    public static Map<String, Double> getCurrentPosition() {
        if (instance != null && instance.flutterView != null) {
            WindowManager.LayoutParams params = (WindowManager.LayoutParams) instance.flutterView.getLayoutParams();
            Map<String, Double> position = new HashMap<>();
            position.put("x", instance.pxToDp(params.x));
            position.put("y", instance.pxToDp(params.y));
            return position;
        }
        return null;
    }

    public static boolean moveOverlay(int x, int y) {
        if (instance != null && instance.flutterView != null) {
            if (instance.windowManager != null) {
                WindowManager.LayoutParams params = (WindowManager.LayoutParams) instance.flutterView.getLayoutParams();
                params.x = (x == -1999 || x == -1) ? -1 : instance.dpToPx(x);
                params.y = instance.dpToPx(y);
                instance.clampOverlayPosition(params);
                instance.windowManager.updateViewLayout(instance.flutterView, params);
                return true;
            } else {
                return false;
            }
        } else {
            return false;
        }
    }


    @Override
    public void onCreate() {
        super.onCreate();
        // Get the cached FlutterEngine
        FlutterEngine flutterEngine = FlutterEngineCache.getInstance().get(OverlayConstants.CACHED_TAG);

        if (flutterEngine == null) {
            // Handle the error if engine is not found
            Log.e("OverlayService", "Flutter engine not found, hence creating new flutter engine");
            FlutterEngineGroup engineGroup = new FlutterEngineGroup(this);
            DartExecutor.DartEntrypoint entryPoint = new DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                "overlayMain"
            );  // "overlayMain" is custom entry point

            flutterEngine = engineGroup.createAndRunEngine(this, entryPoint);

            // Cache the created FlutterEngine for future use
            FlutterEngineCache.getInstance().put(OverlayConstants.CACHED_TAG, flutterEngine);
        }

        // Create the MethodChannel with the properly initialized FlutterEngine
        if (flutterEngine != null) {
            flutterChannel = new MethodChannel(flutterEngine.getDartExecutor(), OverlayConstants.OVERLAY_TAG);
            overlayMessageChannel = new BasicMessageChannel(flutterEngine.getDartExecutor(), OverlayConstants.MESSENGER_TAG, JSONMessageCodec.INSTANCE);
            registerOverlayBridge(flutterEngine);
        }

        createNotificationChannel();
        Intent notificationIntent = new Intent(this, FlutterOverlayWindowPlugin.class);
        int pendingFlags;
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            pendingFlags = PendingIntent.FLAG_IMMUTABLE;
        } else {
            pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT;
        }
        PendingIntent pendingIntent = PendingIntent.getActivity(this,
                0, notificationIntent, pendingFlags);
        final int notifyIcon = getDrawableResourceId("mipmap", "launcher");
        Notification notification = new NotificationCompat.Builder(this, OverlayConstants.CHANNEL_ID)
                .setContentTitle(WindowSetup.overlayTitle)
                .setContentText(WindowSetup.overlayContent)
                .setSmallIcon(notifyIcon == 0 ? R.drawable.notification_icon : notifyIcon)
                .setContentIntent(pendingIntent)
                .setVisibility(WindowSetup.notificationVisibility)
                .build();
        startForeground(OverlayConstants.NOTIFICATION_ID, notification);
        instance = this;
    }

    /** G?n OverlayBridge l?n overlay engine ?? n?t ch?o/t?m bi?t g?i native d? app ? n?n. */
    private void registerOverlayBridge(FlutterEngine flutterEngine) {
        try {
            Class<?> bridgeClass = Class.forName("com.hicar.ora.limited.OverlayBridge");
            java.lang.reflect.Method register = bridgeClass.getMethod(
                    "register", FlutterEngine.class, Context.class);
            register.invoke(null, flutterEngine, getApplicationContext());
        } catch (Exception e) {
            diagnosticError("overlay_bridge_register", e);
        }
    }

    private void diagnosticError(String stage, Exception error) {
        String message = "mode=android_screen_mode stage=" + stage + " " + Log.getStackTraceString(error);
        Log.e("OverlayBridge", message);
        try {
            Class<?> log = Class.forName("com.hicar.ora.limited.HiCarDiagnosticLog");
            Object logger = log.getField("INSTANCE").get(null);
            log.getMethod("init", Context.class).invoke(logger, getApplicationContext());
            log.getMethod("e", String.class, String.class).invoke(logger, "OverlayBridge", message);
        } catch (Exception ignored) { /* Logcat remains available if app bridge is unavailable. */ }
    }

    private int dragSlopPxSq() {
        int slop = dpToPx((int) DRAG_SLOP_DP);
        return slop * slop;
    }

    private boolean isTopLeftGravity(WindowManager.LayoutParams params) {
        int g = params.gravity;
        return (g & Gravity.TOP) != 0 && (g & Gravity.LEFT) != 0;
    }

    /** T?nh bi?n k?o m?t l?n khi ch?m ? d?ng l?i su?t gesture. */
    private void cacheDragBounds(WindowManager.LayoutParams params) {
        refreshScreenSize();
        int viewWidth = overlayViewWidth(params);
        int viewHeight = overlayViewHeight(params);
        int edgeMargin = dpToPx(16);
        int topBound = statusBarHeightPx() + edgeMargin;
        int bottomBound = szWindow.y - (inPortrait() ? navigationBarHeightPx() : 0) - edgeMargin;
        int leftBound = edgeMargin;
        int rightBound = Math.max(leftBound, szWindow.x - edgeMargin);
        dragMinX = leftBound;
        dragMinY = topBound;
        dragMaxX = Math.max(leftBound, rightBound - viewWidth);
        dragMaxY = Math.max(topBound, bottomBound - viewHeight);
    }

    private void clampParamsTopLeft(WindowManager.LayoutParams params) {
        if (params.x < dragMinX) params.x = dragMinX;
        else if (params.x > dragMaxX) params.x = dragMaxX;
        if (params.y < dragMinY) params.y = dragMinY;
        else if (params.y > dragMaxY) params.y = dragMaxY;
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel serviceChannel = new NotificationChannel(
                    OverlayConstants.CHANNEL_ID,
                    "Foreground Service Channel",
                    NotificationManager.IMPORTANCE_DEFAULT
            );
            NotificationManager manager = getSystemService(NotificationManager.class);
            assert manager != null;
            manager.createNotificationChannel(serviceChannel);
        }
    }

    private int getDrawableResourceId(String resType, String name) {
        return getApplicationContext().getResources().getIdentifier(String.format("ic_%s", name), resType, getApplicationContext().getPackageName());
    }

    private int dpToPx(int dp) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP,
                Float.parseFloat(dp + ""), mResources.getDisplayMetrics());
    }

    private double pxToDp(int px) {
        return (double) px / mResources.getDisplayMetrics().density;
    }

    private boolean inPortrait() {
        return mResources.getConfiguration().orientation == Configuration.ORIENTATION_PORTRAIT;
    }

    /** C?p nh?t k?ch th??c m?n h?nh (xoay ngang/d??c tr?n m?n xe). */
    private void refreshScreenSize() {
        if (windowManager == null) return;
        DisplayMetrics dm = new DisplayMetrics();
        windowManager.getDefaultDisplay().getRealMetrics(dm);
        szWindow.set(dm.widthPixels, dm.heightPixels);
    }

    /** Kh?ng d?ng LAYOUT_NO_LIMITS khi k?o ? flag n?y cho ph?p window tr?i ra ngo?i m?n h?nh. */
    private int buildWindowFlags() {
        int flags = WindowSetup.flag
                | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                | WindowManager.LayoutParams.FLAG_LAYOUT_INSET_DECOR
                | WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED;
        if (!WindowSetup.enableDrag) {
            flags |= WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS;
        }
        return flags;
    }

    private int overlayViewWidth(WindowManager.LayoutParams params) {
        int w = flutterView != null ? flutterView.getWidth() : 0;
        if (w <= 0 && params.width > 0) w = params.width;
        if (w <= 0) w = dpToPx(80);
        return w;
    }

    private int overlayViewHeight(WindowManager.LayoutParams params) {
        int h = flutterView != null ? flutterView.getHeight() : 0;
        if (h <= 0 && params.height > 0) h = params.height;
        if (h <= 0) h = dpToPx(170);
        return h;
    }

    /**
     * Gi? n?t n?i trong v?ng hi?n th? ? clamp theo v? tr? th?c tr?n m?n h?nh (getLocationOnScreen),
     * kh?ng ph? thu?c getWidth()/getHeight() l?c drag (th???ng = 0 ? clamp c? b? b?? qua).
     */
    private void clampOverlayPosition(WindowManager.LayoutParams params) {
        if (flutterView == null || windowManager == null || params == null) return;
        if (!WindowSetup.enableDrag) return;

        refreshScreenSize();

        int viewWidth = overlayViewWidth(params);
        int viewHeight = overlayViewHeight(params);

        int[] location = new int[2];
        flutterView.getLocationOnScreen(location);
        int left = location[0];
        int top = location[1];

        int edgeMargin = dpToPx(16);
        int topBound = statusBarHeightPx() + edgeMargin;
        int bottomBound = szWindow.y - (inPortrait() ? navigationBarHeightPx() : 0) - edgeMargin;
        int leftBound = edgeMargin;
        int rightBound = Math.max(leftBound, szWindow.x - edgeMargin);

        int maxLeft = Math.max(leftBound, rightBound - viewWidth);
        int maxTop = Math.max(topBound, bottomBound - viewHeight);

        int clampedLeft = Math.max(leftBound, Math.min(left, maxLeft));
        int clampedTop = Math.max(topBound, Math.min(top, maxTop));

        if (clampedLeft == left && clampedTop == top) return;

        applyScreenPositionToParams(params, clampedLeft, clampedTop, viewWidth, viewHeight);
    }

    private void applyScreenPositionToParams(
            WindowManager.LayoutParams params, int left, int top, int viewWidth, int viewHeight) {
        int screenW = szWindow.x;
        int screenH = szWindow.y;
        int gravity = params.gravity;

        if ((gravity & Gravity.RIGHT) != 0 && (gravity & Gravity.LEFT) == 0) {
            params.x = screenW - viewWidth - left;
        } else {
            params.x = left;
        }

        int verticalGravity = gravity & Gravity.VERTICAL_GRAVITY_MASK;
        if (verticalGravity == Gravity.CENTER_VERTICAL) {
            params.y = top + viewHeight / 2 - screenH / 2;
        } else if ((gravity & Gravity.TOP) != 0) {
            params.y = top;
        } else if ((gravity & Gravity.BOTTOM) != 0) {
            params.y = screenH - viewHeight - top;
        } else {
            params.y = top + viewHeight / 2 - screenH / 2;
        }
    }

    @Override
    public void onConfigurationChanged(Configuration newConfig) {
        super.onConfigurationChanged(newConfig);
        if (flutterView != null && windowManager != null) {
            WindowManager.LayoutParams params = (WindowManager.LayoutParams) flutterView.getLayoutParams();
            clampOverlayPosition(params);
            windowManager.updateViewLayout(flutterView, params);
        }
    }

    /** Native drag updates LayoutParams directly; always return false for Flutter taps. */
    @Override
    public boolean onTouch(View view, MotionEvent event) {
        if (windowManager == null || !WindowSetup.enableDrag) {
            return false;
        }
        WindowManager.LayoutParams params = (WindowManager.LayoutParams) flutterView.getLayoutParams();
        switch (event.getAction()) {
            case MotionEvent.ACTION_DOWN:
                dragging = false;
                touchDownRawX = event.getRawX();
                touchDownRawY = event.getRawY();
                lastX = event.getRawX();
                lastY = event.getRawY();
                cacheDragBounds(params);
                return false;
            case MotionEvent.ACTION_MOVE:
                float dxFromDown = event.getRawX() - touchDownRawX;
                float dyFromDown = event.getRawY() - touchDownRawY;
                if (dxFromDown * dxFromDown + dyFromDown * dyFromDown < dragSlopPxSq()) {
                    return false;
                }
                float dx = event.getRawX() - lastX;
                float dy = event.getRawY() - lastY;
                lastX = event.getRawX();
                lastY = event.getRawY();

                if (isTopLeftGravity(params)) {
                    params.x += (int) dx;
                    params.y += (int) dy;
                    clampParamsTopLeft(params);
                } else {
                    int viewWidth = overlayViewWidth(params);
                    int viewHeight = overlayViewHeight(params);
                    int[] location = new int[2];
                    flutterView.getLocationOnScreen(location);
                    int newLeft = location[0] + (int) dx;
                    int newTop = location[1] + (int) dy;
                    newLeft = Math.max(dragMinX, Math.min(newLeft, dragMaxX));
                    newTop = Math.max(dragMinY, Math.min(newTop, dragMaxY));
                    applyScreenPositionToParams(params, newLeft, newTop, viewWidth, viewHeight);
                }
                windowManager.updateViewLayout(flutterView, params);
                dragging = true;
                return false;
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_CANCEL:
                if (dragging) {
                    lastYPosition = params.y;
                    if (!WindowSetup.positionGravity.equals("none")) {
                        mTrayTimerTask = new TrayAnimationTimerTask();
                        mTrayAnimationTimer = new Timer();
                        mTrayAnimationTimer.schedule(mTrayTimerTask, 0, 25);
                    }
                }
                dragging = false;
                return false;
            default:
                return false;
        }
    }

    private class TrayAnimationTimerTask extends TimerTask {
        int mDestX;
        int mDestY;
        WindowManager.LayoutParams params = (WindowManager.LayoutParams) flutterView.getLayoutParams();

        public TrayAnimationTimerTask() {
            super();
            mDestY = lastYPosition;
            switch (WindowSetup.positionGravity) {
                case "auto":
                    mDestX = (params.x + (flutterView.getWidth() / 2)) <= szWindow.x / 2 ? 0 : szWindow.x - flutterView.getWidth();
                    break;
                case "left":
                    mDestX = 0;
                    break;
                case "right":
                    mDestX = szWindow.x - flutterView.getWidth();
                    break;
                default:
                    mDestX = params.x;
                    mDestY = params.y;
                    break;
            }
            WindowManager.LayoutParams dest = new WindowManager.LayoutParams();
            dest.copyFrom(params);
            dest.x = mDestX;
            dest.y = mDestY;
            clampOverlayPosition(dest);
            mDestX = dest.x;
            mDestY = dest.y;
        }

        @Override
        public void run() {
            mAnimationHandler.post(() -> {
                params.x = (2 * (params.x - mDestX)) / 3 + mDestX;
                params.y = (2 * (params.y - mDestY)) / 3 + mDestY;
                clampOverlayPosition(params);
                if (windowManager != null) {
                    windowManager.updateViewLayout(flutterView, params);
                }
                if (Math.abs(params.x - mDestX) < 2 && Math.abs(params.y - mDestY) < 2) {
                    TrayAnimationTimerTask.this.cancel();
                    mTrayAnimationTimer.cancel();
                }
            });
        }
    }


}
