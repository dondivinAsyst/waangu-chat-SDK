# Public/Sync
Status: BUILT (ChatSyncRunner). Wiring in the host app is the host's decision.
ChatSyncRunner.syncNow() = outbox flush then missed-event pull. stop() cancels. It starts no live stream: ChatFeature keeps the live inbox subscription, so the host builds its FeatureSyncEngine with liveUpdates: false.

ChatSessionLifecycle (step 1.8) is what the host calls when its session changes: userDidSignIn(), appDidEnterForeground(), appDidEnterBackground(), userDidSignOut(). It connects realtime (only if a chat token is still valid), requests a sync, keeps realtime up in background while a call is active, and on sign-out stops the sync before it disconnects. Build it with the realtime client, a ChatSyncRunner and the chat token manager. The host keeps its own analytics, crash reporting and other features' sync in its session code.
