const std = @import("std");
const compat = @import("compat.zig");
const zigVersionCompare = compat.zigVersionCompare;

pub const LifetimeConfig = struct {
    child_allocator: std.mem.Allocator = std.heap.page_allocator,
    parent_lifetime: ?type = null,
};
fn fmtSrc(comptime src: std.builtin.SourceLocation) [:0]const u8 {
    return std.fmt.comptimePrint(
        "{s} |zaman> {s}:{}:{}",
        .{ src.module, src.file, src.line, src.column },
    );
}
pub fn Lifetime(comptime s: std.builtin.SourceLocation, comptime config: LifetimeConfig) type {
    return LifetimeI(fmtSrc(s), config);
}
fn LifetimeI(comptime lifetime_loc: [:0]const u8, comptime config: LifetimeConfig) type {
    return struct {
        pub const ParentLifetime = config.parent_lifetime;
        threadlocal var arena: std.heap.ArenaAllocator = .init(config.child_allocator);
        const Error = std.mem.Allocator.Error;
        const ___SRC_LOC___ = lifetime_loc;
        pub const Allocator = BoundedAllocatorI(lifetime_loc);
        pub fn allocator() Allocator {
            return .{ .allocator = arena.allocator() };
        }
        pub fn deinit() void {
            _ = arena.reset(.retain_capacity);
        }
        pub fn deinitRelease() void {
            _ = arena.reset(.free_all);
        }

        pub fn Bound(T: type) type {
            return Bounded(T, lifetime_loc);
        }
        pub fn create(V: type) Error!Bound(*V) {
            return allocator().create(V);
        }
        pub fn alloc(V: type, n: usize) Error!Bound([]V) {
            return allocator().alloc(V, n);
        }
        pub fn allocSentinel(V: type, n: usize, comptime sentinel: V) Error!Bound([:sentinel]V) {
            return allocator().allocSentinel(V, n, sentinel);
        }
        pub fn dupe(V: type, m: []const V) Error!Bound([]V) {
            return allocator().dupe(V, m);
        }
        pub fn dupeZ(V: type, m: []const V) Error!Bound([:0]V) {
            return allocator().dupeZ(V, m);
        }
    };
}
fn BoundedAllocatorI(comptime lifetime: [:0]const u8) type {
    return struct {
        const Error = std.mem.Allocator.Error;
        allocator: std.mem.Allocator,
        pub fn Bound(T: type) type {
            return Bounded(T, lifetime);
        }
        pub inline fn create(self: @This(), V: type) Error!Bound(*V) {
            return .{ .p = try self.allocator.create(V) };
        }
        pub inline fn alloc(self: @This(), V: type, n: usize) Error!Bound([]V) {
            return .{ .p = try self.allocator.alloc(V, n) };
        }
        pub inline fn allocSentinel(self: @This(), V: type, n: usize, comptime sentinel: V) Error!Bound([:sentinel]V) {
            return .{ .p = try self.allocator.allocSentinel(V, n, sentinel) };
        }
        pub inline fn dupe(self: @This(), V: type, m: []const V) Error!Bound([]V) {
            return .{ .p = try self.allocator.dupe(V, m) };
        }
        pub inline fn dupeZ(self: @This(), V: type, m: []const V) Error!Bound([:0]V) {
            return .{ .p = try self.allocator.dupeZ(V, m) };
        }
    };
}
fn Bounded(V: type, comptime lifetime: [:0]const u8) type {
    const vtinfo = @typeInfo(V);
    if (vtinfo != .pointer) @compileError("T should be pointer or slice");
    const p = vtinfo.pointer;
    if (p.size == .c)
        @compileError("C-Pointers are not supported");
    return struct {
        p: V,
        const ConstT =
            if (p.size == .one)
                *const p.child
            else if (p.size == .slice)
                if (p.sentinel()) |s| [:s]const p.child else []const p.child
            else if (p.sentinel()) |s| [*:s]const p.child else [*]p.child;
        pub fn intoConst(self: @This()) Bounded(ConstT, lifetime) {
            return .{ .p = self.p };
        }
        fn FTyp(comptime field_name: [:0]const u8) type {
            const Ft = @FieldType(p.child, field_name);
            return if (p_is_const) *const Ft else *Ft;
        }
        inline fn fieldFn(self: @This(), comptime field_name: [:0]const u8) Bounded(FTyp(field_name), lifetime) {
            return .{ .p = &@field(self.p.*, field_name) };
        }
        pub inline fn bound(self: @This(), L: type) L.Bound(V) {
            comptime check_LTree: {
                var Li = L;
                while (true) {
                    if (std.mem.eql(u8, Li.___SRC_LOC___, lifetime)) break :check_LTree;
                    Li = Li.ParentLifetime orelse break;
                }
                @compileError(std.fmt.comptimePrint(
                    \\ Lifetime({s}) is not containing Lifetime({s})
                    \\    hint: you should specify the "parent_lifetime" property for
                    \\          your Lifetimes so the checker can ensure the correct usage
                ,
                    .{ lifetime, L.___SRC_LOC___ },
                ));
            }
            return .{ .p = self.p };
        }
        const SemVer = std.SemanticVersion;
        const p_is_const =
            if (zigVersionCompare(.gte, "0.17.0-dev"))
                p.attrs.@"const"
            else
                p.is_const; // older api
        const Ch =
            if (p.size == .one)
                switch (@typeInfo(p.child)) {
                    .array => |a| if (p_is_const) *const a.child else *a.child,
                    else => @compileError("incompatible"),
                }
            else if (p_is_const) *const p.child else *p.child;
        const Chs =
            if (p.size == .one)
                switch (@typeInfo(p.child)) {
                    .array => |a| if (p_is_const) []const a.child else []a.child,
                    else => @compileError("incompatible"),
                }
            else if (p_is_const) []const p.child else []p.child;
        const ChsE =
            if (p.size == .one) switch (@typeInfo(p.child)) {
                .array => |a| if (p_is_const)
                    if (a.sentinel()) |s| [:s]const a.child else []const a.child
                else if (a.sentinel()) |s| [:s]a.child else []a.child,
                else => @compileError("incompatible"),
            } else V;
        inline fn indexFn(self: @This(), i: usize) Bounded(Ch, lifetime) {
            return .{ .p = &self.p[i] };
        }
        inline fn lenFn(self: @This()) usize {
            return self.p.len;
        }
        inline fn sliceFn(self: @This(), from: usize, to: usize) Bounded(Chs, lifetime) {
            return .{ .p = self.p[from..to] };
        }
        inline fn sliceFromFn(self: @This(), from: usize) Bounded(ChsE, lifetime) {
            return .{ .p = self.p[from..] };
        }
        inline fn setFn(self: @This(), value: p.child) void {
            self.p.* = value;
        }
        inline fn getFn(self: @This()) p.child {
            return self.p.*;
        }
        const single_access = p.size == .one and @typeInfo(p.child) != .array;
        pub const field =
            if (single_access) fieldFn else @compileError("Cannot take field from slice");
        pub const index =
            if (single_access) @compileError("Cannot take index from a single-item ptr") else indexFn;
        pub const slice =
            if (single_access) @compileError("Cannot take slice from a single-item ptr") else sliceFn;
        pub const sliceFrom =
            if (single_access) @compileError("Cannot take slice from a single-item ptr") else sliceFromFn;
        pub const len =
            if (single_access) @compileError("Len isn't defined for single-item ptr") else lenFn;
        pub const set =
            if (p_is_const)
                @compileError("Cannot write to a const ptr")
            else if (p.size != .one) @compileError("Cannot write to a many-item ptr") else setFn;
        pub const get =
            if (p.size != .one) @compileError("Cannot write to a many-item ptr") else getFn;
    };
}

test "function signature" {
    const X = struct {
        fn foo(L: type, x: L.Bound(*i32)) !L.Bound(*i32) {
            const La = Lifetime(@src(), .{});
            defer La.deinit();

            x.set(x.get() + 10);
            // const y = try La.create(i32); //=> compile-error
            const y = try L.create(i32);

            y.set(2 * x.get());
            return y;
        }
        fn bar(L: type, alloc: L.Allocator, x: L.Bound(*i32)) !L.Bound(*i32) {
            const La = Lifetime(@src(), .{});
            defer La.deinit();

            x.set(x.get() + 10);
            // const y = try La.create(i32); //=> compile-error
            const y = try alloc.create(i32);

            y.set(2 * x.get());
            return y;
        }
        fn baz(alloc: anytype, x: @TypeOf(alloc).Bound(*i32)) !@TypeOf(alloc).Bound(*const i32) {
            const La = Lifetime(@src(), .{});
            defer La.deinit();

            x.set(x.get() + 10);
            // const y = try La.create(i32); //=> compile-error
            const y = try alloc.create(i32);

            y.set(2 * x.get());
            return y.intoConst();
        }
    };

    const La = Lifetime(@src(), .{});
    defer La.deinit();

    const x = try La.create(i32);
    x.set(10);
    const y = try X.foo(La, x);
    try std.testing.expectEqual(20, x.get());
    try std.testing.expectEqual(40, y.get());

    const z = try X.bar(La, La.allocator(), x);
    try std.testing.expectEqual(30, x.get());
    try std.testing.expectEqual(60, z.get());

    const w = try X.baz(La.allocator(), x);
    try std.testing.expectEqual(40, x.get());
    try std.testing.expectEqual(80, w.get());
}

test "lifetime in action" {
    const La = Lifetime(@src(), .{});
    defer La.deinit();

    const l = try La.allocator().alloc(i32, 100);
    for (l.p, 1..) |*x, i| {
        x.* = @intCast(i);
    }

    var some: La.Bound(*i32) = undefined;

    for (0..100) |_| {
        const Lb = Lifetime(@src(), .{});
        defer Lb.deinit();

        // some = try Lb.create(i32); // compile-error
        some = try La.create(i32);

        for (0..10) |_| {
            const x = try Lb.create(i32);
            try std.testing.expectEqual(Lb.Bound(*i32), @TypeOf(x));
            // std.debug.print("{} ", .{x.p});
        }
        // std.debug.print("\n", .{});

        for (0..10) |_| {
            const Lc = Lifetime(@src(), .{});
            defer Lc.deinit();

            for (0..10) |_| {
                const x = try Lc.create(i32);
                try std.testing.expectEqual(Lc.Bound(*i32), @TypeOf(x));
                // std.debug.print("{} ", .{x.p});
            }
            // std.debug.print("\n", .{});
        }
    }
}

test "bounded slices" {
    const La = Lifetime(@src(), .{});
    defer La.deinit();

    const st = try La.create(struct {
        name: La.Bound([]u8),
        id: usize,
    });
    st.p.name = try La.dupe(u8, "salam");
    st.p.id = 10;

    const stname = st.field("name").p;
    try std.testing.expectEqual(*La.Bound([]u8), @TypeOf(stname));
    const stid = st.field("id");
    try std.testing.expectEqual(La.Bound(*usize), @TypeOf(stid));
    // std.debug.print("{s} : {}\n", .{ stname.p, stid.p.* });

    const arr = try La.create([10:0]u8);
    @memcpy(arr.p[0..5], "salam");
    arr.p[5] = 0;

    const arr0 = arr.index(0);
    try std.testing.expectEqual(La.Bound(*u8), @TypeOf(arr0));
    // std.debug.print("{c}", .{arr0.p.*});

    const arr05 = arr.slice(0, 5);
    try std.testing.expectEqual(La.Bound([]u8), @TypeOf(arr05));
    // std.debug.print("{s}", .{arr05.p});

    const arr2_ = arr.sliceFrom(2);
    try std.testing.expectEqual(La.Bound([:0]u8), @TypeOf(arr2_));
    // std.debug.print("{s}", .{arr2_.p});
}

test "bounded usage" {
    const L = Lifetime(@src(), .{});
    defer L.deinit();

    const xp: L.Bound(*u32) = try L.create(u32);
    xp.set(10);
    const x: u32 = xp.get();
    try std.testing.expectEqual(10, x);

    const S = struct {
        a: u32,
        b: u32,
    };
    const sp: L.Bound(*S) = try L.create(S);
    sp.set(S{ .a = 1, .b = 2 });
    const afp: L.Bound(*u32) = sp.field("a");
    const a: u32 = afp.get();
    const b: u32 = sp.field("b").get();
    try std.testing.expectEqual(1, a);
    try std.testing.expectEqual(2, b);
    try std.testing.expectEqual(S{ .a = 1, .b = 2 }, sp.get());

    const ap = try L.create([4]u32);
    ap.set([4]u32{ 1, 2, 3, 4 });
    ap.index(0).set(5);
    try std.testing.expectEqual([4]u32{ 5, 2, 3, 4 }, ap.get());
    try std.testing.expectEqual(4, ap.len());

    const sl: L.Bound([]u8) = try L.dupe(u8, "salam");
    try std.testing.expectEqual(5, sl.len());
    sl.index(0).set('h');
    try std.testing.expectEqualSlices(u8, "halam", sl.p);
    const subsl: L.Bound([]u8) = sl.slice(1, 3);
    @memcpy(subsl.p, "xa");
    try std.testing.expectEqualSlices(u8, "hxaam", sl.p);
}

test "type missmatch" {
    const La, const Lb = .{ Lifetime(@src(), .{}), Lifetime(@src(), .{}) };
    defer La.deinit();
    defer Lb.deinit();

    try std.testing.expect(La != Lb);
    try std.testing.expect(@TypeOf(La.allocator()) != @TypeOf(Lb.allocator()));
    try std.testing.expect(La.Bound(*i32) != Lb.Bound(*i32));
}

fn longest(A: type, x: A.Bound([]u8), y: A.Bound([]u8)) A.Bound([]u8) {
    return if (x.len() > y.len()) x else y;
}
test "rust-book sample1" {
    const La = Lifetime(@src(), .{});
    defer La.deinit();

    const string1 = try La.dupe(u8, "long string is long");

    {
        const Lb = Lifetime(@src(), .{ .parent_lifetime = La });
        defer Lb.deinit();

        const string2 = try Lb.dupe(u8, "xyz");
        const result = longest(Lb, string1.bound(Lb), string2);
        _ = result; // autofix
        // std.debug.print("The longest string is {s}", .{result.p});
    }
}

fn ImportantExcerpt(A: type) type {
    return struct {
        part: A.Bound([]const u8),
        fn announce_and_return_part(self: *const @This(), announcement: []const u8) A.Bound([]const u8) {
            std.debug.print("Attention please: {}", .{announcement});
            return self.part;
        }
    };
}

test "rust-book sample2" {
    const La = Lifetime(@src(), .{});
    defer La.deinit();

    const novel = try La.dupe(u8, "Call me Ishmael. Some years ago...");
    var spl = std.mem.splitScalar(u8, novel.p, '.');
    const first_sentence = spl.next().?;
    const i = ImportantExcerpt(La){
        .part = .{ .p = first_sentence },
    };
    _ = i; // autofix
}

fn first_word(A: type, s: A.Bound([]const u8)) A.Bound([]const u8) {
    for (s.p, 0..) |item, i| {
        if (item == ' ') {
            return s.slice(0, i);
        }
    }
    return s;
}
test "rust-book sample3" {
    const La = Lifetime(@src(), .{});
    defer La.deinit();

    _ = first_word(La, (try La.dupe(u8, "salam")).intoConst());
}

fn indexer(A: type, array: A.Bound([]const i32), i: *const usize) A.Bound(*const i32) {
    return array.index(i.*);
}
test "indexer" {
    const La = Lifetime(@src(), .{});
    const res = indexer(La, (try La.dupe(i32, &.{ 1, 2, 3 })).intoConst(), &0);
    try std.testing.expectEqual(1, res.get());
}

fn threadedLt(io: std.Io) !void {
    var iorng = std.Random.IoSource{ .io = io };
    const rng = iorng.interface();
    const Lt = Lifetime(@src(), .{});
    defer Lt.deinit();

    const test_vector = rng.array(u64, 1 << 14);

    var barr: [32]struct { usize, usize } = undefined;
    var parr: [32][]u64 = undefined;
    const cnt = rng.intRangeAtMostBiased(usize, 5, 20);
    for (0..cnt) |i| {
        const xx = rng.uintAtMostBiased(usize, @min(1 << 14, @as(usize, 1) << @intCast(6 + @divFloor(i, 2))));
        const yy = rng.uintAtMostBiased(usize, @min(1 << 14, @as(usize, 1) << @intCast(6 + @divFloor(i, 2))));
        const l, const r = .{ @min(xx, yy), @max(xx, yy) };
        const p = try Lt.alloc(u64, r - l);
        barr[i] = .{ l, r };
        parr[i] = p.p;
        @memcpy(p.p, test_vector[l..r]);
        try io.sleep(.fromNanoseconds(rng.intRangeAtMostBiased(i96, 10, 2000)), .real);
        try std.testing.expectEqualSlices(u64, test_vector[l..r], p.p);
        try std.testing.expectEqual(.{ l, r }, barr[i]);
        try std.testing.expectEqual(p.p, parr[i]);
    }
    for (barr[0..cnt], parr[0..cnt]) |b, p| {
        try std.testing.expectEqualSlices(u64, test_vector[b[0]..b[1]], p);
    }
}
fn threadedEntry(io: std.Io) std.Io.Cancelable!void {
    threadedLt(io) catch |e| {
        switch (e) {
            error.Canceled => return error.Canceled,
            else => {
                std.debug.dumpCurrentStackTrace(.{});
                @panic("failed");
            },
        }
    };
}
test "mutli-threaded" {
    if (comptime zigVersionCompare(.gte, "0.16.0-dev")) {
        var g = std.Io.Group.init;
        for (0..1000) |_| {
            try g.concurrent(std.testing.io, threadedEntry, .{std.testing.io});
        }
        try g.await(std.testing.io);
    }
}
