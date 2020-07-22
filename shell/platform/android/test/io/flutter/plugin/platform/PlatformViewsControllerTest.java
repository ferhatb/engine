package io.flutter.plugin.platform;

import static io.flutter.embedding.engine.systemchannels.PlatformViewsChannel.PlatformViewTouch;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.mockito.Matchers.eq;
import static org.mockito.Mockito.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import android.content.Context;
import android.content.res.AssetManager;
import android.view.MotionEvent;
import android.view.View;
import io.flutter.embedding.android.FlutterView;
import io.flutter.embedding.android.MotionEventTracker;
import io.flutter.embedding.engine.FlutterJNI;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.StandardMethodCodec;
import java.nio.ByteBuffer;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;
import org.junit.Ignore;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;

@Config(manifest = Config.NONE)
@RunWith(RobolectricTestRunner.class)
public class PlatformViewsControllerTest {

  @Ignore
  @Test
  public void itNotifiesVirtualDisplayControllersOfViewAttachmentAndDetachment() {
    // Setup test structure.
    // Create a fake View that represents the View that renders a Flutter UI.
    View fakeFlutterView = new View(RuntimeEnvironment.systemContext);

    // Create fake VirtualDisplayControllers. This requires internal knowledge of
    // PlatformViewsController. We know that all PlatformViewsController does is
    // forward view attachment/detachment calls to it's VirtualDisplayControllers.
    //
    // TODO(mattcarroll): once PlatformViewsController is refactored into testable
    // pieces, remove this test and avoid verifying private behavior.
    VirtualDisplayController fakeVdController1 = mock(VirtualDisplayController.class);
    VirtualDisplayController fakeVdController2 = mock(VirtualDisplayController.class);

    // Create the PlatformViewsController that is under test.
    PlatformViewsController platformViewsController = new PlatformViewsController();

    // Manually inject fake VirtualDisplayControllers into the PlatformViewsController.
    platformViewsController.vdControllers.put(0, fakeVdController1);
    platformViewsController.vdControllers.put(1, fakeVdController1);

    // Execute test & verify results.
    // Attach PlatformViewsController to the fake Flutter View.
    platformViewsController.attachToView(fakeFlutterView);

    // Verify that all virtual display controllers were notified of View attachment.
    verify(fakeVdController1, times(1)).onFlutterViewAttached(eq(fakeFlutterView));
    verify(fakeVdController1, never()).onFlutterViewDetached();
    verify(fakeVdController2, times(1)).onFlutterViewAttached(eq(fakeFlutterView));
    verify(fakeVdController2, never()).onFlutterViewDetached();

    // Detach PlatformViewsController from the fake Flutter View.
    platformViewsController.detachFromView();

    // Verify that all virtual display controllers were notified of the View detachment.
    verify(fakeVdController1, times(1)).onFlutterViewAttached(eq(fakeFlutterView));
    verify(fakeVdController1, times(1)).onFlutterViewDetached();
    verify(fakeVdController2, times(1)).onFlutterViewAttached(eq(fakeFlutterView));
    verify(fakeVdController2, times(1)).onFlutterViewDetached();
  }

  @Ignore
  @Test
  public void itCancelsOldPresentationOnResize() {
    // Setup test structure.
    // Create a fake View that represents the View that renders a Flutter UI.
    View fakeFlutterView = new View(RuntimeEnvironment.systemContext);

    // Create fake VirtualDisplayControllers. This requires internal knowledge of
    // PlatformViewsController. We know that all PlatformViewsController does is
    // forward view attachment/detachment calls to it's VirtualDisplayControllers.
    //
    // TODO(mattcarroll): once PlatformViewsController is refactored into testable
    // pieces, remove this test and avoid verifying private behavior.
    VirtualDisplayController fakeVdController1 = mock(VirtualDisplayController.class);

    SingleViewPresentation presentation = fakeVdController1.presentation;

    fakeVdController1.resize(10, 10, null);

    assertEquals(fakeVdController1.presentation != presentation, true);
    assertEquals(presentation.isShowing(), false);
  }

  @Test
  public void itUsesActionEventTypeFromFrameworkEventForVirtualDisplays() {
    MotionEventTracker motionEventTracker = MotionEventTracker.getInstance();
    PlatformViewsController platformViewsController = new PlatformViewsController();

    MotionEvent original =
        MotionEvent.obtain(
            100, // downTime
            100, // eventTime
            1, // action
            0, // x
            0, // y
            0 // metaState
            );

    // track an event that will later get passed to us from framework
    MotionEventTracker.MotionEventId motionEventId = motionEventTracker.track(original);

    PlatformViewTouch frameWorkTouch =
        new PlatformViewTouch(
            0, // viewId
            original.getDownTime(),
            original.getEventTime(),
            2, // action
            1, // pointerCount
            Arrays.asList(Arrays.asList(0, 0)), // pointer properties
            Arrays.asList(Arrays.asList(0., 1., 2., 3., 4., 5., 6., 7., 8.)), // pointer coords
            original.getMetaState(),
            original.getButtonState(),
            original.getXPrecision(),
            original.getYPrecision(),
            original.getDeviceId(),
            original.getEdgeFlags(),
            original.getSource(),
            original.getFlags(),
            motionEventId.getId());

    MotionEvent resolvedEvent =
        platformViewsController.toMotionEvent(
            1, // density
            frameWorkTouch,
            true // usingVirtualDisplays
            );

    assertEquals(resolvedEvent.getAction(), frameWorkTouch.action);
    assertNotEquals(resolvedEvent.getAction(), original.getAction());
  }

  @Ignore
  @Test
  public void itUsesActionEventTypeFromMotionEventForHybridPlatformViews() {
    MotionEventTracker motionEventTracker = MotionEventTracker.getInstance();
    PlatformViewsController platformViewsController = new PlatformViewsController();

    MotionEvent original =
        MotionEvent.obtain(
            100, // downTime
            100, // eventTime
            1, // action
            0, // x
            0, // y
            0 // metaState
            );

    // track an event that will later get passed to us from framework
    MotionEventTracker.MotionEventId motionEventId = motionEventTracker.track(original);

    PlatformViewTouch frameWorkTouch =
        new PlatformViewTouch(
            0, // viewId
            original.getDownTime(),
            original.getEventTime(),
            2, // action
            1, // pointerCount
            Arrays.asList(Arrays.asList(0, 0)), // pointer properties
            Arrays.asList(Arrays.asList(0., 1., 2., 3., 4., 5., 6., 7., 8.)), // pointer coords
            original.getMetaState(),
            original.getButtonState(),
            original.getXPrecision(),
            original.getYPrecision(),
            original.getDeviceId(),
            original.getEdgeFlags(),
            original.getSource(),
            original.getFlags(),
            motionEventId.getId());

    MotionEvent resolvedEvent =
        platformViewsController.toMotionEvent(
            1, // density
            frameWorkTouch,
            false // usingVirtualDisplays
            );

    assertNotEquals(resolvedEvent.getAction(), frameWorkTouch.action);
    assertEquals(resolvedEvent.getAction(), original.getAction());
  }

  @Test
  public void getPlatformViewById__hybridComposition() {
    PlatformViewsController platformViewsController = new PlatformViewsController();

    int platformViewId = 0;
    assertNull(platformViewsController.getPlatformViewById(platformViewId));

    FlutterJNI jni = new FlutterJNI();
    AssetManager assetManager = mock(AssetManager.class);
    Context context = RuntimeEnvironment.application.getApplicationContext();

    DartExecutor executor = new DartExecutor(jni, assetManager);
    executor.onAttachedToJNI();
    platformViewsController.attach(context, null, executor);
    platformViewsController.attachToView(mock(FlutterView.class));

    PlatformViewFactory viewFactory = mock(PlatformViewFactory.class);
    PlatformView platformView = mock(PlatformView.class);
    View androidView = mock(View.class);
    when(platformView.getView()).thenReturn(androidView);
    when(viewFactory.create(any(), eq(platformViewId), any())).thenReturn(platformView);

    platformViewsController.getRegistry().registerViewFactory("testType", viewFactory);

    // Simulate create call from the framework.
    Map<String, Object> platformViewCreateArguments = new HashMap<>();
    platformViewCreateArguments.put("hybrid", true);
    platformViewCreateArguments.put("id", platformViewId);
    platformViewCreateArguments.put("viewType", "testType");
    platformViewCreateArguments.put("direction", 0);
    MethodCall platformCreateMethodCall = new MethodCall("create", platformViewCreateArguments);

    jni.handlePlatformMessage(
        "flutter/platform_views", encodeMethodCall(platformCreateMethodCall), /*replyId=*/ 0);

    platformViewsController.initializePlatformViewIfNeeded(platformViewId);

    View resultAndroidView = platformViewsController.getPlatformViewById(platformViewId);
    assertNotNull(resultAndroidView);
    assertEquals(resultAndroidView, androidView);
  }

  private static byte[] encodeMethodCall(MethodCall call) {
    ByteBuffer buffer = StandardMethodCodec.INSTANCE.encodeMethodCall(call);
    buffer.rewind();
    byte[] dest = new byte[buffer.remaining()];
    buffer.get(dest);
    return dest;
  }
}
