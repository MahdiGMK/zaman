const std = @import("std");
pub const LifetimeConfig = struct {
    parent_allocator: std.mem.Allocator = std.heap.page_allocator,
    parent_lifetime: ?type = null,
};
pub fn Lifetime(comptime s: std.builtin.SourceLocation, comptime config: LifetimeConfig) type {
    return struct {
        const ___SRC_LOC___ = s;
        pub const ParentLifetime = config.parent_lifetime;
        var arena: std.heap.ArenaAllocator = .init(config.parent_allocator);
        const Error = std.mem.Allocator.Error;
        pub fn allocator() BoundedAllocator(@This()) {
            return .{ .allocator = arena.allocator() };
        }
        pub fn deinit() void {
            _ = arena.reset(.retain_capacity);
        }
        pub fn deinitRelease() void {
            _ = arena.reset(.free_all);
        }

        pub fn Bound(T: type) type {
            return Bounded(@This(), T);
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
pub fn BoundedAllocator(L: type) type {
    return struct {
        pub const Lifetime = L;
        const Error = std.mem.Allocator.Error;
        allocator: std.mem.Allocator,
        pub fn Bound(T: type) type {
            return Bounded(L, T);
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
pub fn Bounded(L: type, V: type) type {
    const vtinfo = @typeInfo(V);
    if (vtinfo != .pointer) @compileError("T should be pointer or slice");
    const p = vtinfo.pointer;
    if (p.size == .c)
        @compileError("C-Pointers are not supported");
    return struct {
        p: V,
        pub const Lifetime = L;
        const ConstT =
            if (p.size == .one)
                *const p.child
            else if (p.size == .slice)
                if (p.sentinel()) |s| [:s]const p.child else []const p.child
            else if (p.sentinel()) |s| [*:s]const p.child else [*]p.child;
        pub fn intoConst(self: @This()) Bounded(L, ConstT) {
            return .{ .p = self.p };
        }
        fn FTyp(comptime field_name: [:0]const u8) type {
            const Ft = @FieldType(p.child, field_name);
            return if (p.is_const) *const Ft else *Ft;
        }
        inline fn fieldFn(self: @This(), comptime field_name: [:0]const u8) Bounded(L, FTyp(field_name)) {
            return .{ .p = &@field(self.p.*, field_name) };
        }
        const Ch =
            if (p.size == .one)
                switch (@typeInfo(p.child)) {
                    .array => |a| if (p.is_const) *const a.child else *a.child,
                    else => @compileError("incompatible"),
                }
            else if (p.is_const) *const p.child else *p.child;
        const Chs =
            if (p.size == .one)
                switch (@typeInfo(p.child)) {
                    .array => |a| if (p.is_const) []const a.child else []a.child,
                    else => @compileError("incompatible"),
                }
            else if (p.is_const) []const p.child else []p.child;
        const ChsE =
            if (p.size == .one) switch (@typeInfo(p.child)) {
                .array => |a| if (p.is_const)
                    if (a.sentinel()) |s| [:s]const a.child else []const a.child
                else if (a.sentinel()) |s| [:s]a.child else []a.child,
                else => @compileError("incompatible"),
            } else V;
        inline fn indexFn(self: @This(), i: usize) Bounded(L, Ch) {
            return .{ .p = &self.p[i] };
        }
        inline fn sliceFn(self: @This(), from: usize, to: usize) Bounded(L, Chs) {
            return .{ .p = self.p[from..to] };
        }
        inline fn sliceFromFn(self: @This(), from: usize) Bounded(L, ChsE) {
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
        pub const set =
            if (p.is_const)
                @compileError("Cannot write to a const ptr")
            else if (p.size != .one) @compileError("Cannot write to a many-item ptr") else setFn;
        pub const get =
            if (p.size != .one) @compileError("Cannot write to a many-item ptr") else getFn;
    };
}

test "function signature" {
    const X = struct {
        fn foo(L: type, x: Bounded(L, *i32)) !Bounded(L, *i32) {
            const La = Lifetime(@src(), .{});
            defer La.deinit();

            x.set(x.get() + 10);
            // const y = try La.create(i32); //=> compile-error
            const y = try L.create(i32);

            y.set(2 * x.get());
            return y;
        }
        fn bar(L: type, alloc: BoundedAllocator(L), x: Bounded(L, *i32)) !Bounded(L, *i32) {
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

    var some: Bounded(La, *i32) = undefined;

    for (0..100) |_| {
        const Lb = Lifetime(@src(), .{});
        defer Lb.deinit();

        // some = try Lb.create(i32); // compile-error
        some = try La.create(i32);

        for (0..10) |_| {
            const x = try Lb.create(i32);
            try std.testing.expectEqual(Bounded(Lb, *i32), @TypeOf(x));
            // std.debug.print("{} ", .{x.p});
        }
        // std.debug.print("\n", .{});

        for (0..10) |_| {
            const Lc = Lifetime(@src(), .{});
            defer Lc.deinit();

            for (0..10) |_| {
                const x = try Lc.create(i32);
                try std.testing.expectEqual(Bounded(Lc, *i32), @TypeOf(x));
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
        name: Bounded(La, []u8),
        id: usize,
    });
    st.p.name = try La.dupe(u8, "salam");
    st.p.id = 10;

    const stname = st.field("name").p;
    try std.testing.expectEqual(*Bounded(La, []u8), @TypeOf(stname));
    const stid = st.field("id");
    try std.testing.expectEqual(Bounded(La, *usize), @TypeOf(stid));
    // std.debug.print("{s} : {}\n", .{ stname.p, stid.p.* });

    const arr = try La.create([10:0]u8);
    @memcpy(arr.p[0..5], "salam");
    arr.p[5] = 0;

    const arr0 = arr.index(0);
    try std.testing.expectEqual(Bounded(La, *u8), @TypeOf(arr0));
    // std.debug.print("{c}", .{arr0.p.*});

    const arr05 = arr.slice(0, 5);
    try std.testing.expectEqual(Bounded(La, []u8), @TypeOf(arr05));
    // std.debug.print("{s}", .{arr05.p});

    const arr2_ = arr.sliceFrom(2);
    try std.testing.expectEqual(Bounded(La, [:0]u8), @TypeOf(arr2_));
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

    const sl: L.Bound([]u8) = try L.dupe(u8, "salam");
    sl.index(0).set('h');
    try std.testing.expectEqualSlices(u8, "halam", sl.p);
    const subsl: L.Bound([]u8) = sl.slice(1, 3);
    @memcpy(subsl.p, "xa");
    try std.testing.expectEqualSlices(u8, "hxaam", sl.p);
}
