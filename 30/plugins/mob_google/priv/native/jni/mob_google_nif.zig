//! mob_google_nif — Android Sign in with Google tier-1 zig plugin NIF.
//!
//! Same shape as mob_ocr_nif.zig: one async NIF that hands a JSON argument
//! string to the Kotlin bridge `io.mob.google.MobGoogleBridge`, plus two
//! delivery thunks the bridge calls back when the person has chosen.
//!
//! Delivered messages (to the pid that called the NIF):
//!   * {:google, :result, json_binary}
//!   * {:google, :error, json_binary}
const std = @import("std");
const erts = @import("erts");
const jni = @import("jni");

// mob-core exports (linked into the same .so).
extern fn get_jenv(attached: *c_int) ?*jni.JNIEnv;
extern var g_jvm: ?*jni.JavaVM;

var g_google_sign_in: jni.JMethodID = null;
var g_google_cls: jni.JClass = null;

export fn Java_io_mob_google_MobGoogleBridge_nativeRegister(jenv: *jni.JNIEnv, cls: jni.JClass) callconv(.c) void {
    g_google_cls = jni.newGlobalRef(jenv, cls);
    if (g_google_cls == null) return;
    g_google_sign_in = jni.getStaticMethodID(jenv, cls, "google_sign_in", "(JLjava/lang/String;)V");
}

inline fn detachIfAttached(attached: c_int) void {
    if (attached != 0) {
        if (g_jvm) |jvm| jni.detachCurrentThread(jvm);
    }
}

inline fn pidToJlong(pid: erts.ErlNifPid) jni.JLong {
    if (@sizeOf(erts.ERL_NIF_TERM) == @sizeOf(jni.JLong)) {
        return @bitCast(pid.pid);
    }
    return @intCast(pid.pid);
}

inline fn pidFromLong(jpid: jni.JLong) erts.ErlNifPid {
    if (@sizeOf(erts.ERL_NIF_TERM) == @sizeOf(jni.JLong)) {
        return .{ .pid = @bitCast(jpid) };
    }
    const low: u32 = @truncate(@as(u64, @bitCast(jpid)));
    return .{ .pid = low };
}

// Sends {:google, <sub>, json_binary} to `pid_long`.
fn deliver(jenv: *jni.JNIEnv, pid_long: jni.JLong, comptime sub: [:0]const u8, json: jni.JString) void {
    var pid = pidFromLong(pid_long);
    const env = erts.enif_alloc_env() orelse return;
    defer erts.enif_free_env(env);

    const json_c = jenv.*.GetStringUTFChars.?(jenv, json, null) orelse return;
    defer jenv.*.ReleaseStringUTFChars.?(jenv, json, json_c);
    const len = std.mem.len(json_c);

    var bin: erts.ErlNifBinary = undefined;
    if (erts.enif_alloc_binary(len, &bin) == 0) return;
    @memcpy(bin.data[0..len], json_c[0..len]);

    const msg = erts.makeTuple(env, .{
        erts.atom(env, "google"),
        erts.atom(env, sub),
        erts.enif_make_binary(env, &bin),
    });
    _ = erts.enif_send(null, &pid, env, msg);
}

export fn Java_io_mob_google_MobGoogleBridge_nativeDeliverResult(
    jenv: *jni.JNIEnv,
    cls: jni.JClass,
    pid_long: jni.JLong,
    json: jni.JString,
) callconv(.c) void {
    _ = cls;
    deliver(jenv, pid_long, "result", json);
}

export fn Java_io_mob_google_MobGoogleBridge_nativeDeliverError(
    jenv: *jni.JNIEnv,
    cls: jni.JClass,
    pid_long: jni.JLong,
    json: jni.JString,
) callconv(.c) void {
    _ = cls;
    deliver(jenv, pid_long, "error", json);
}

// ── NIF ───────────────────────────────────────────────────────────────────

// The argument JSON (the server client id) is copied into a heap buffer;
// newStringUTF copies synchronously, so the buffer is freed right after.
fn nif_google_sign_in(env: ?*erts.ErlNifEnv, argc: c_int, argv: [*]const erts.ERL_NIF_TERM) callconv(.c) erts.ERL_NIF_TERM {
    _ = argc;
    var bin: erts.ErlNifBinary = undefined;
    if (erts.enif_inspect_binary(env, argv[0], &bin) == 0 and
        erts.enif_inspect_iolist_as_binary(env, argv[0], &bin) == 0) return erts.badarg(env);
    if (g_google_cls == null or g_google_sign_in == null) return erts.atom(env, "error");

    const buf = std.heap.c_allocator.allocSentinel(u8, bin.size, 0) catch return erts.atom(env, "error");
    defer std.heap.c_allocator.free(buf);
    @memcpy(buf[0..bin.size], bin.data[0..bin.size]);

    var pid: erts.ErlNifPid = undefined;
    _ = erts.enif_self(env, &pid);

    var attached: c_int = 0;
    const jenv = get_jenv(&attached) orelse return erts.atom(env, "error");
    const jarg = jni.newStringUTF(jenv, buf.ptr);
    jenv.*.CallStaticVoidMethod.?(jenv, g_google_cls, g_google_sign_in, pidToJlong(pid), jarg);
    if (jarg != null) jni.deleteLocalRef(jenv, jarg);
    detachIfAttached(attached);
    return erts.ok(env);
}

fn nifLoad(env: ?*erts.ErlNifEnv, priv: *?*anyopaque, info: erts.ERL_NIF_TERM) callconv(.c) c_int {
    _ = env;
    _ = priv;
    _ = info;
    return 0;
}

const nif_funcs = [_]erts.ErlNifFunc{
    .{ .name = "google_sign_in", .arity = 1, .fptr = nif_google_sign_in, .flags = 0 },
};

var nif_entry: erts.ErlNifEntry = .{
    .major = erts.ERL_NIF_MAJOR_VERSION,
    .minor = erts.ERL_NIF_MINOR_VERSION,
    .name = "mob_google_nif",
    .num_of_funcs = nif_funcs.len,
    .funcs = &nif_funcs,
    .load = nifLoad,
    .reload = null,
    .upgrade = null,
    .unload = null,
    .vm_variant = erts.ERL_NIF_VM_VARIANT,
    .options = 1,
    .sizeof_ErlNifResourceTypeInit = erts.SIZEOF_ErlNifResourceTypeInit,
    .min_erts = erts.ERL_NIF_MIN_ERTS_VERSION,
};

pub export fn mob_google_nif_nif_init() callconv(.c) *erts.ErlNifEntry {
    return &nif_entry;
}
