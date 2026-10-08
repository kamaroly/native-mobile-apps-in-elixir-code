%% mob_google_nif — Erlang NIF stub for the mob_google plugin.
%%
%% Android: priv/native/jni/mob_google_nif.zig bridging to the Kotlin
%% io.mob.google.MobGoogleBridge (Credential Manager, Sign in with Google).
%% There is no iOS implementation yet, and on a host dev build nothing is
%% linked, so on_load tolerates the failure and calls raise nif_not_loaded
%% (MobGoogle turns that into a {:google, :error, ...} message).
-module(mob_google_nif).
-export([google_sign_in/1]).
-on_load(init/0).

init() ->
    case erlang:load_nif("mob_google_nif", 0) of
        ok -> ok;
        {error, _} -> ok
    end.

google_sign_in(_ArgsJson) ->
    erlang:nif_error(nif_not_loaded).
