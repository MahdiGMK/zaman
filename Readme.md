# Zaman

_**Comptime lifetime annotations for Zig!**_

Zaman (زمان in Persian) is a memory safety tool for Zig that tries to
prevent use-after-free and lifetime confusion at compile time by encoding arena lifetimes directly into pointer types.

```zig
const La = Lifetime(@src(), .{});
defer La.deinit();

const x = try La.create(i32);
var y = try La.create(i32);

// x and y share the Lifetime La

const Lb = Lifetime(@src(), .{});
defer Lb.deinit();

const z = try Lb.create(i32);
y = z; // compilation error!
// z has the Lifetime Lb != La
```

## Example of use-after-free prevention

```zig
const La = Lifetime(@src(), .{});
defer La.deinit();

var use_after_free: La.Bound(*u32) = undefined;
{
    const Lb = Lifetime(@src(), .{});
    defer Lb.deinit();

    const x = try Lb.create(u32);
    x.set(10);
    use_after_free = x;
}
std.debug.print("{}\n", use_after_free.get());
```

compilation output

```
src/uaf.zig:14:26: error: expected type 'lifetime.Bounded(*u32,"uaf |zaman> uaf.zig:4:25"[0..24])',
                                  found 'lifetime.Bounded(*u32,"uaf |zaman> uaf.zig:9:29"[0..24])'
        use_after_free = x;
                         ^
src/lifetime.zig:84:12: note: struct declared here (2 times)
    return struct {
           ^~~~~~
```

## Comparison with Rust

Here we compare some rust examples from the RustBook and the equivilant Zaman usage.

### longest<'a>(x: &'a str, y: &'a str) -> &'a str

Rust version

```rust
fn longest<'a>(x: &'a str, y: &'a str) -> &'a str {
    if x.len() > y.len() { x } else { y }
}
fn main() {
    let string1 = String::from("long string is long");

    {
        let string2 = String::from("xyz");
        let result = longest(string1.as_str(), string2.as_str());
        println!("The longest string is {result}");
    }
}
```

Zaman version

```zig
fn longest(A: type, x: A.Bound([]u8), y: A.Bound([]u8)) A.Bound([]u8) {
    return if (x.len() > y.len()) x else y;
}
pub fn main() void {
    const La = Lifetime(@src(), .{});
    defer La.deinit();

    const string1 = try La.dupe(u8, "long string is long");

    {
        const Lb = Lifetime(@src(), .{ .parent_lifetime = La }); // required for bound operation
        defer Lb.deinit();

        const string2 = try Lb.dupe(u8, "xyz");
        const result = longest(Lb, string1.bound(Lb), string2);
        std.debug.print("The longest string is {s}", .{result.p});
    }
}
```

Both compile successfully and output the same

```
The longest string is long string is long
```

And also use-after-free prevention

```zig
fn longest(A: type, x: A.Bound([]u8), y: A.Bound([]u8)) A.Bound([]u8) {
    return if (x.len() > y.len()) x else y;
}
pub fn main() !void {
    const La = Lifetime(@src(), .{});
    defer La.deinit();

    const string1 = try La.dupe(u8, "long string is long");

    var result: La.Bound([]u8) = undefined;
    {
        const Lb = Lifetime(@src(), .{ .parent_lifetime = La }); // required for bound operation
        defer Lb.deinit();

        const string2 = try Lb.dupe(u8, "xyz");
        result = longest(Lb, string1.bound(Lb), string2);
    }
    std.debug.print("The longest string is {s}", .{result.p});
}
```

compiler output

```
src/uaf.zig:20:25: error: expected type 'lifetime.Bounded([]u8,"uaf |zaman> uaf.zig:9:25"[0..24])',
                                  found 'lifetime.Bounded([]u8,"uaf |zaman> uaf.zig:16:29"[0..25])'
        result = longest(Lb, string1.bound(Lb), string2);
                 ~~~~~~~^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
src/lifetime.zig:82:12: note: struct declared here (2 times)
    return struct {
           ^~~~~~
```

### struct ImportantExcerpt<'a>

Rust version

```rust
struct ImportantExcerpt<'a> {
    part: &'a str,
}
fn main() {
    let novel = String::from("Call me Ishmael. Some years ago...");
    let first_sentence = novel.split('.').next().unwrap();
    let i = ImportantExcerpt {
        part: first_sentence,
    };
}
```

Zaman version

```zig
fn ImportantExcerpt(A: type) type {
    return struct { part: A.Bound([]const u8) };
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
    _ = i;
}
```

### fn first_word<'a>(s: &'a str) -> &'a str

Rust version

```rust
fn first_word<'a>(s: &'a str) -> &'a str {
    let bytes = s.as_bytes();

    for (i, &item) in bytes.iter().enumerate() {
        if item == b' ' {
            return &s[0..i];
        }
    }

    &s[..]
}
```

Zaman

```zig
fn first_word(A: type, s: A.Bound([]const u8)) A.Bound([]const u8) {
    for (s.p, 0..) |item, i| {
        if (item == ' ') {
            return s.slice(0, i);
        }
    }
    return s;
}
```

### impl<'a> ImportantExcerpt<'a>

Rust version

```rust
struct ImportantExcerpt<'a> {
    part: &'a str,
}
impl<'a> ImportantExcerpt<'a> {
    fn announce_and_return_part(&self, announcement: &str) -> &str {
        println!("Attention please: {announcement}");
        self.part
    }
}
```

Zaman version

```zig
fn ImportantExcerpt(A: type) type {
    return struct {
        part: A.Bound([]const u8),
        fn announce_and_return_part(self: *const @This(), announcement: []const u8) A.Bound([]const u8) {
            std.debug.print("Attention please: {}", .{announcement});
            return self.part;
        }
    };
}
```

_**Note**_: this sample is used in the RustBook to explain Lifetime Elision but we can't support it!

## How it works

Each `Lifetime(@src(), .{})` call produces a unique lifetime type. `Bounded(*T, L)` binds a pointer or slice to a specific lifetime `L` through Zig's type system. Cross-lifetime assignments produce compile errors because the types don't match — no runtime overhead, no footguns.

### Why?

Manual memory management is fine and manageable — but sometimes you need stronger guarantees, and eyeballing the code isn't enough. Zaman makes use-after-frees a _compile error_, not a segfault. No runtime checking, no tracing, no borrowing rules to learn. Just normal Zig types.

## Other use-cases

You can also use zaman lifetimes when you need an arena that doesn't release its memory when the function ends - reducing the allocation count to O(1) amortized.

```zig
fn foo() void {
    const L = Lifetime(@src(), .{});
    defer L.deinit(); // arena.reset(.retain_capacity)
    // or L.deinitRelease() to fully release memory

    const bounded_allocator = L.allocator();
    const allocator: std.mem.Allocator = bounded_allocator.allocator;
    // ...
}
```

## Installation

1. Add zaman as a dependency in your build.zig.zon:

```
zig fetch --save "git+https://github.com/MahdiGMK/zaman#master"
```

2. In your build.zig, add the zaman module as a dependency of your program:

```zig
const zaman = b.dependency("zaman", .{
    .target = target,
    .optimize = optimize,
});

// the executable from your call to b.addExecutable(...)
exe.root_module.addImport("zaman", zaman.module("zaman"));
```

## Guide

### Lifetime

```zig
const L = Lifetime(@src(), .{});
defer L.deinit();                // arena.reset(retain_capacity)
// or `defer L.deinitRelease();` // arena.reset(free_all)

// your typical Allocator functions
const x = try L.create(i32);
const xs = try L.alloc(i32, 128);
const xd = try L.dupe(i32, xs);
// ...
```

```zig
fn foo(L: type, arg: u32) !L.Bound(*u32) {
    const La = Lifetime(@src(), .{});
    defer La.deinit();

    // const x = try La.create(u32); //=> compile error
    const x = try L.create(u32);
    x.set(arg * 2);
    return x;
}
```

### Bounded Pointer

Standard operations on Bounded pointers

- get
- set
- field
- index
- slice
- sliceFrom
- len
- bound

```zig
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
```

#### The bound operation

Using the bound operation, you can safely transition between different lifetimes.

```zig
const La = Lifetime(@src(), .{});
defer La.deinit();

const xa = try La.create(u32);
{
    const Lb = Lifetime(@src(), .{ .parent_lifetime = La }); // forms a tree of nested lifetimes
    defer Lb.deinit();

    const yb = try Lb.create(u32);

    const xb = xa.bound(Lb); // safe and sound
    const ya = yb.bound(La); // compile error
}
```

compiler output

```
src/lifetime.zig:107:17: error:  Lifetime(uaf |zaman> uaf.zig:12:29) is not containing Lifetime(uaf |zaman> uaf.zig:7:25)
                                    hint: you should specify the "parent_lifetime" property for
                                          your Lifetimes so the checker can ensure the correct usage
                @compileError(std.fmt.comptimePrint(
                ^~~~~~~~~~~~~
src/uaf.zig:19:28: note: called inline here
        const ya = yb.bound(La); // compile error
                   ~~~~~~~~^~~~
```

#### Using other libraries that need std.mem.Allocator

You can get the internal allocator of a lifetime via
`L.allocator().allocator`
and use it with other containers and libraries.

_**Note**_: be careful with this escape hatch — lifetime guarantees are your responsibility once you bypass `Bounded`.

#### What is considered 'unsafe'?

- manual creation of `L.Bound(P)` objects
- escaping `bounded.p` internal pointers
- using lifetime's internal arena allocator

#### What does it mean for an operation to be 'unsafe'?

Zig is unsafe by nature so it doesn't have any negative meaning
with respect to the language semantics itself.
But considering the guarantees that Zaman can give you about memory safety, these operations are beyond what it can do and guarantee. So YOU should pay as much attention to them as your normal every-day Zig code!

### Bounded Allocator

Using lifetime types directly in generic function signatures can cause binary bloat — each lifetime instantiates a separate copy of the function (compiler-dependent).

`BoundedAllocator` has the exact same in-memory representation as a plain `std.mem.Allocator`, so the compiler has an easier time deduplicating instantiations.

_**Note**_: This behaviour is not guaranteed — it depends on the compiler's optimiser.

```zig
fn foo1(L: type, allocator: BoundedAllocator(L)) !L.Bound(*u32) {
    // ...
}
fn foo2(allocator: anytype) !@TypeOf(allocator).Bound(*u32) {
    // ...
}

test "bounded allocators" {
    const L = Lifetime(@src(), .{});
    defer L.deinit();

    const bounded_allocator = L.allocator();
    _ = try foo1(L, bounded_allocator);
    _ = try foo2(bounded_allocator);
    // ...
}
```

## What could be next?

I have ideas around concurrency safety using similar ideas — but nothing implemented yet!
