package com.ofsgames.lumabounce.review;

import android.app.Activity;

import com.google.android.play.core.review.ReviewInfo;
import com.google.android.play.core.review.ReviewManager;
import com.google.android.play.core.review.ReviewManagerFactory;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.util.Collections;
import java.util.Set;
import java.util.concurrent.atomic.AtomicBoolean;

/** Minimal Google Play Review bridge. A completed flow does not prove a rating. */
public final class LumaReviewPlugin extends GodotPlugin {
    private static final String PLUGIN_NAME = "LumaReviewPlugin";
    private static final String SIGNAL_FINISHED = "review_flow_finished";

    private final AtomicBoolean busy = new AtomicBoolean(false);

    public LumaReviewPlugin(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return PLUGIN_NAME;
    }

    @Override
    public Set<SignalInfo> getPluginSignals() {
        return Collections.singleton(new SignalInfo(SIGNAL_FINISHED, Boolean.class));
    }

    @UsedByGodot
    public boolean requestReview() {
        if (!busy.compareAndSet(false, true)) {
            return false;
        }
        final Activity activity = getActivity();
        if (activity == null) {
            busy.set(false);
            return false;
        }
        runOnUiThread(() -> requestAndLaunch(activity));
        return true;
    }

    @UsedByGodot
    public boolean isBusy() {
        return busy.get();
    }

    private void requestAndLaunch(Activity activity) {
        final ReviewManager manager = ReviewManagerFactory.create(activity);
        manager.requestReviewFlow().addOnCompleteListener(request -> {
            if (!request.isSuccessful()) {
                finish(false);
                return;
            }
            final ReviewInfo info = request.getResult();
            manager.launchReviewFlow(activity, info).addOnCompleteListener(
                    flow -> finish(flow.isSuccessful()));
        });
    }

    private void finish(boolean completed) {
        if (!busy.compareAndSet(true, false)) {
            return;
        }
        emitSignal(SIGNAL_FINISHED, completed);
    }
}
