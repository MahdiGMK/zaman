const std = @import("std");

pub fn Guarded(Mutex: type, Value: type) type {
    return struct {
        mutex: Mutex,
        value: Value,
        pub fn init(mutex: Mutex, value: Value) @This() {
            return .{
                .value = value,
                .mutex = mutex,
            };
        }
        pub fn lock(self: *@This()) UniqueAccess(Mutex, Value) {
            self.mutex.lock();
            return .{ .ref = self };
        }
        pub fn tryLock(self: *@This()) ?UniqueAccess(Mutex, Value) {
            if (self.mutex.tryLock())
                return .{ .ref = self };
            return null;
        }
    };
}
pub fn UniqueAccess(Mutex: type, Value: type) type {
    return struct {
        ref: ?*Guarded(Mutex, Value),
        pub fn unlock(self: *@This()) void {
            if (self.ref) |ref| ref.mutex.unlock();
            self.ref = null;
        }
        pub fn getRef(self: *@This()) ?*const Value {
            if (self.ref) |ref| return &ref.value;
            return null;
        }
        pub fn get(self: @This()) ?Value {
            if (self.ref) |ref| return ref.value;
            return null;
        }
        pub fn set(self: @This(), new_value: Value) !void {
            if (self.ref) |ref| {
                ref.value = new_value;
            } else return error.NoUniqueAccess;
        }
        fn MethodReturn(comptime method_name: [:0]const u8) type {
            return @typeInfo(@TypeOf(@field(Value, method_name))).@"fn".return_type.?;
        }
        pub fn call(self: @This(), comptime method_name: [:0]const u8, arguments: anytype) !MethodReturn(method_name) {
            if (self.ref) |ref| {
                const function = @field(Value, method_name);
                const FirstArgT = @typeInfo(@TypeOf(function)).@"fn".params[0].type.?;
                if (FirstArgT == Value) {
                    return @call(.always_inline, function, .{ref.value} ++ arguments);
                } else if (FirstArgT == *Value or FirstArgT == *const Value) {
                    return @call(.always_inline, function, .{&ref.value} ++ arguments);
                } else @compileError("Function \"" ++ method_name ++ "\" is not a method (first arg is not of type Value)");
            } else return error.NoUniqueAccess;
        }
        pub fn modify(self: @This(), new_values: anytype) !void {
            if (self.ref) |ref| {
                const tinfo = @typeInfo(@TypeOf(new_values));
                inline for (tinfo.@"struct".fields) |fld| {
                    @field(ref.value, fld.name) = @field(new_values, fld.name);
                }
            } else return error.NoUniqueAccess;
        }
    };
}

test "lock guard" {
    const S = struct {
        f1: i32,
        f2: u32,
        pub fn meth0(self: @This()) i32 {
            return self.f1;
        }
        pub fn meth1(self: *const @This()) u32 {
            return self.f2;
        }
        pub fn meth2(self: *@This()) !void {
            self.f1 += 1;
            self.f2 -= 1;
        }
    };
    var guarded = Guarded(std.Thread.Mutex, S).init(.{}, .{ .f1 = 0, .f2 = 0 });
    {
        var access = guarded.lock();
        defer access.unlock();

        access.modify(.{ .f2 = 2 }) catch unreachable;
        const f1 = access.call("meth0", .{}) catch unreachable;
        try std.testing.expectEqual(0, f1);
        const f2 = access.call("meth1", .{}) catch unreachable;
        try std.testing.expectEqual(2, f2);
        try access.call("meth2", .{}) catch unreachable;
        {
            const x = access.get().?;
            try std.testing.expectEqual(S{ .f1 = 1, .f2 = 1 }, x);
        }
    }
}
