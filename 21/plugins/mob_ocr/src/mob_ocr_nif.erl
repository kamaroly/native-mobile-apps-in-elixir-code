%% mob_ocr_nif — Erlang NIF stub for the mob_ocr plugin.
%%
%% Android: priv/native/jni/mob_ocr_nif.zig bridging to the Kotlin
%% io.mob.ocr.MobOcrBridge (ML Kit text recognition + barcode scanning).
%% There is no iOS implementation yet, and on a host dev build nothing is
%% linked, so on_load tolerates the failure and calls raise nif_not_loaded
%% (MobOcr turns that into an {:ocr, :error, ...} message).
-module(mob_ocr_nif).
-export([ocr_process/1]).
-on_load(init/0).

init() ->
    case erlang:load_nif("mob_ocr_nif", 0) of
        ok -> ok;
        {error, _} -> ok
    end.

ocr_process(_ArgsJson) ->
    erlang:nif_error(nif_not_loaded).
