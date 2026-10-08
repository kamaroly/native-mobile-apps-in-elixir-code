%% mob_viewer_nif — Erlang NIF stub for the mob_viewer plugin.
%%
%% Android: priv/native/jni/mob_viewer_nif.zig bridging to the Kotlin
%% io.mob.viewer.MobViewerBridge. On iOS and host builds nothing is linked,
%% so on_load tolerates the failure and calls raise nif_not_loaded (MobViewer
%% turns that into a {:viewer, :error, ...} message).
-module(mob_viewer_nif).
-export([view_file/1]).
-on_load(init/0).

init() ->
    case erlang:load_nif("mob_viewer_nif", 0) of
        ok -> ok;
        {error, _} -> ok
    end.

view_file(_ArgsJson) ->
    erlang:nif_error(nif_not_loaded).
