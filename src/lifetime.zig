const std = @import("std");
pub fn Lifetime(comptime s: std.builtin.SourceLocation) type {
    return struct {
        const ___SRC_LOC___ = s;
        var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
        const Error = std.mem.Allocator.Error;
        pub fn allocator() std.mem.Allocator {
            return arena.allocator();
        }
        fn B(T: type) type {
            return Bounded(@This(), T);
        }
        pub fn create(V: type) Error!B(*V) {
            return .{ .p = try arena.allocator().create(V) };
        }
        pub fn alloc(V: type, n: usize) Error!B([]V) {
            return .{ .p = try arena.allocator().alloc(V, n) };
        }
        pub fn allocSentinel(V: type, n: usize, comptime sentinel: V) Error!B([:sentinel]V) {
            return .{ .p = try arena.allocator().allocSentinel(V, n, sentinel) };
        }
        pub fn dupe(V: type, m: []const V) Error!B([]V) {
            return .{ .p = try arena.allocator().dupe(V, m) };
        }
        pub fn dupeZ(V: type, m: []const V) Error!B([:0]V) {
            return .{ .p = try arena.allocator().dupeZ(V, m) };
        }
        pub fn deinit() void {
            _ = arena.reset(.retain_capacity);
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
        const single_access = p.size == .one and @typeInfo(p.child) != .array;
        pub const field =
            if (single_access) fieldFn else @compileError("Cannot take field from slice");
        pub const index =
            if (single_access) @compileError("Cannot take index from single ptr") else indexFn;
        pub const slice =
            if (single_access) @compileError("Cannot take slice from single ptr") else sliceFn;
        pub const sliceFrom =
            if (single_access) @compileError("Cannot take slice from single ptr") else sliceFromFn;
    };
}

test "lifetime in action" {
    const La = Lifetime(@src());
    defer La.deinit();

    const l = try La.alloc(i32, 100);
    for (l.p, 1..) |*x, i| {
        x.* = @intCast(i);
    }

    var some: Bounded(La, *i32) = undefined;

    for (0..100) |_| {
        const Lb = Lifetime(@src());
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
            const Lc = Lifetime(@src());
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
    const La = Lifetime(@src());
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
