const std = @import("std");
const vec2 = @import("vec2.zig");
const Vec2 = vec2.Vec2;
const Vec2F = vec2.Vec2F;

const alloc = std.heap.page_allocator;

pub fn Tree() type {
    return struct {
        /// Building block of the quad tree.
        /// Node is wether a branch or leaf.
        pub const Node = union(enum) {
            const Branch =
                struct {
                // Queadtree needs to reference subnodes
                children: [4]?*Node,
                /// Center of mass in region
                /// If tree is not finalized, than centerOfMass is nothing but
                /// sum of positions multiplied by their mass each.
                /// In order to get actual center of mass we need to devide it by total mass
                /// We dont do this until tree is structured, because we need to add bodies.
                centerOfMass: Vec2,
                // Total mass
                mass: u32,
                /// Width and Height occupied by this branch
                size: u32,
                /// Find out in which quadrant should we put node with given position
                pub fn which(self: @This(), position: Vec2) u2 {
                    const node = Node{ .branch = self };
                    return node.which(position);
                }
            };
            const Leaf = struct {
                //
                mass: u32 = 0,
                position: Vec2 = .{},
                /// Quadrant size
                size: u32,
            };

            // Enum / Union Variants
            leaf: Leaf,
            branch: Branch,
            /// Split leaf on branch and move body to new leaf
            /// Transform leaf to the branch
            /// Also allocate a new leaf
            fn split(self: *@This()) !void {
                // TODO: Not leaf check

                // Allocate
                var node = try ally.create(Node);
                node.* = Node{ .leaf = .{ .size = 0 } };
                var leaf = &node.leaf;

                leaf.* = self.leaf;

                var branch = Branch{
                    // We will push leaf to corresponding child later
                    .children = .{null} ** 4,
                    // Center of mass does not change, since we have only one leaf at the moment
                    // Only the next iteration should modify center of mass
                    .centerOfMass = leaf.position,
                    .mass = leaf.mass,
                    .size = leaf.size,
                };

                self.* = Node{ .branch = branch };

                // TODO: Safetychecks on 0
                if (leaf.size == 1) {
                    return;
                }
                leaf.size /= 2;

                // Ask a new branch where to put leaf
                const quadrant = branch.which(leaf.position);

                // TODO: Move into leaf struct itself
                // Fit leaf's position to new quadrant which is 2 times smaller
                leaf.position = leaf.position.fit(leaf.size);
                // var newNode = ally.alloc(Node, 1);

                // self.position.fit();
                // TODO: Should be This with modified position
                self.branch.children[quadrant] = node;
                // return branch;
            }

            fn newLeaf(mass: u32, position: Vec2) Node {
                return .{
                    .leaf = .{
                        //
                        .mass = mass,
                        .position = position,
                    },
                };
            }

            fn size(self: @This()) u32 {
                return switch (self) {
                    inline else => |case| case.size,
                };
            }

            /// Find out in which quadrant should we put node with given position
            /// Can return error if position is out of bound
            fn which(self: @This(), position: Vec2) u2 {
                const half = self.size() / 2;
                const x: u2 = if (position.x < half) 0 else 1;
                const y: u2 = if (position.y < half) 0 else 1;
                return (x + y * 2);
            }

            /// Show what are spatial coordinates of child
            fn where(self: @This(), quadrant: u2) Vec2 {
                //
                const i = quadrant;
                const s = self.size() / 2;

                // Reference implementation from Venx:
                // UVec3::new(i & 1, (i >> 1) & 1,
                var v = Vec2{ //
                    .x = i & 1,
                    .y = (i >> 1) & 1,
                };
                v.x *= s;
                v.y *= s;
                return v;
            }
        };

        const Self = @This();

        // TODO: Find better allocator
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        const ally = arena.allocator();

        root: ?*Node = null,
        /// Must be fraction of 2. e.g.:
        /// 16, 32, 64, 128, 256, 512, 1024,
        /// And not:
        /// 3, 88, 194, 666, 777
        size: u32,
        final: bool = false,

        /// Create new QuadTree
        pub fn init(comptime size: u32) !Self {
            // TODO: Use math.isPowOfTwo
            if (!((size & (size - 1)) == 0)) {
                @compileError("Bad value, size should be a power of two.");
            }
            return .{ .size = size };
        }
        /// Deinit QuadTree
        pub fn deinit(_: @This()) void {
            arena.deinit();
        }

        pub fn print(self: Self) !void {
            try @import("pretty").print(alloc, self, .{ .max_depth = 0 });
        }

        /// Add Astronomical Body to the System
        pub fn addBody(self: *@This(), mass: u32, position: Vec2) !void {
            if (position.max() >= self.size) {
                return ErrorError.PositionOutOfBound;
            }
            try Tree().visitNode(&self.root, mass, position, self.size);
        }

        fn visitNode(node: *?*Node, mass: u32, position: Vec2, size: u32) !void {
            if (node.*) |n| {
                // There is already node on the given spot
                // TODO: Throw runtime error or warning
                // TODO: refactor
                switch (n.*) {
                    // We dont care if its branch,
                    // Cuz if it is, than there is more than one leaf and we cannot determine if position is actually the same
                    .leaf => |leaf| {
                        if (position.x == leaf.position.x and position.y == leaf.position.y) {
                            return ErrorError.BodyAtGivenPositionAlreadyExist;
                        }
                    },
                    else => {},
                }

                // In *which* *quadrant* do we want to put this node
                const quadrant = n.which(position);

                // If we have our node being something (not a null) we always need it to be a branch.
                // But it can be a Branch or a Leaf.
                // We dont want it to be a Leaf, so in case it is, we just split it.

                switch (n.*) {
                    // Split and move current leaf one level below
                    .leaf => try n.split(),
                    else => {},
                }

                var br = &n.branch;

                // Call it recursivly
                try Tree().visitNode(
                    // Formatter
                    // &branch.children[quadrant],
                    @constCast(&br.children[quadrant]),
                    // Why are you
                    mass,
                    // Not working correctly??
                    position.fit(size / 2),
                    //
                    size / 2,
                );
                // Add mass
                // Its actually pretty clever solution.
                // As you can see, we dont want to change branches (modify its mass or/and center of mass)
                // until we know that we place new node.
                // In some cases we dont want to place a node and return an error.
                // In order for this to work we put mass and center of mass modification logic after recursion
                // In other words if `try` statement above will fail, this mass modificatin will not occure and tree wont be modified
                // But if it works correctly we use stacked values to modify needed values in inverted order (from bottom to up).
                br.mass += mass;
                var cm = &br.centerOfMass;
                cm.x += position.x * mass;
                cm.y += position.y * mass;
            }
            // Here our journey ends. We found a null node and can use it.
            else {
                const newNode = try ally.create(Node);
                newNode.* = Node{
                    .leaf = .{
                        //
                        .mass = mass,
                        .position = position,
                        .size = size,
                    },
                };
                node.* = newNode;
            }
        }

        /// Convert position and node full size
        fn which(position: Vec2, size: u32) u2 {
            const half = size / 2;
            const x: u2 = if (position.x < half) 0 else 1;
            const y: u2 = if (position.y < half) 0 else 1;
            return (x + y * 2);
        }
        /// Internal index of node converted to normalized vector
        // pub fn get_child_position(i: u32) -> UVec3 {
        //     UVec3::new(i & 1, (i >> 1) & 1, (i >> 2) & 1)
        // }
        // /// Convert position of node in 3d space coordinate to internal child branch index
        // pub fn get_child_index(pos: UVec3, level: usize) -> usize {
        //     let child_size = 1 << level;
        //     let x = if pos.x < child_size { 0 } else { 1 };
        //     let y = if pos.y < child_size { 0 } else { 1 };
        //     let z = if pos.z < child_size { 0 } else { 1 };
        //     (x + y * 2 + z * 4) as usize
        // }

        /// Delete all bodies
        pub fn clean(self: *Self) void {
            // TODO: Memory leak possibility
            self.root = null;
        }

        /// Make a step in simulation
        /// Delta needed to make it smooth
        /// For example if program runs at 60 fps, than delta will be 16ms
        const stepArgs = struct {
            force: *Vec2F,
            bodyPos: Vec2,
            bodyMass: u32,
        };
        pub fn step(self: Self, delta: f32, args: stepArgs) void {
            _ = delta; // autofix
            // self.traverse(a);
            self.traverseArgs(calcForces, args) catch unreachable;
        }

        pub fn finalize(self: *Self) void {
            self.final = true;
            // Self.visitNodeTraverse(@constCast(&self.root), .{}, finalizeCB, .{});
            self.traverseArgs(finalizeCB, .{}) catch unreachable;
        }

        fn calcForces(node: *Node, position: Vec2, args: stepArgs) bool {
            switch (node.*) {
                // TODO: Refactor
                .leaf => |leaf| {
                    // _ = leaf; // autofix

                    // TODO: Use float for better accuracy
                    const distance: f32 = @floatFromInt(args.bodyPos.distance(position));

                    std.debug.print("Distance: {d}\n", .{distance});

                    if (distance == 0) {
                        return true;
                    }

                    const bMass: f32 = @floatFromInt(args.bodyMass);
                    const lMass: f32 = @floatFromInt(leaf.mass);

                    // std.debug.print("GenForce: {d}\n", .{generalForce});

                    const otherPX: f32 = @floatFromInt(position.x);
                    const otherPY: f32 = @floatFromInt(position.y);

                    const selfPX: f32 = @floatFromInt(args.bodyPos.x);
                    const selfPY: f32 = @floatFromInt(args.bodyPos.y);

                    const dx = otherPX - selfPX;
                    const dy = otherPY - selfPY;

                    const forceX: f32 = (bMass * lMass) / dx;
                    const forceY: f32 = (bMass * lMass) / dy;

                    // const genForceFloat: f32 = @floatFromInt(generalForce);
                    // const generalForce = 9;

                    // TODO: Implement generalForce to directionalForce
                    const directionalForce: Vec2F = .{ .x = forceX, .y = forceY };

                    args.force.* = directionalForce;
                },
                .branch => {},
            }

            return true;
        }

        pub fn showBounds(self: Self, callb: anytype) !void {
            try self.traverseArgs(treeBoundsCB, callb);
        }

        fn treeBoundsCB(node: *Node, position: Vec2, callb: anytype) void {
            switch (node.*) {
                // TODO: Refactor
                .branch => {},
                .leaf => |leaf| {
                    // given position includes position of body
                    // But we need just position of leaf
                    var nonBodyPos: Vec2 = position;
                    nonBodyPos.x -= leaf.position.x;
                    nonBodyPos.y -= leaf.position.y;
                    callb(nonBodyPos, leaf.size);
                },
            }
        }

        pub fn finalizeCB(node: *Node, _: Vec2, _: anytype) bool {
            // std.Thread.spawn(, , )
            // std.debug.print("HOWOO", .{});
            switch (node.*) {
                // TODO: Refactor
                .leaf => {},
                .branch => {
                    var cm = &node.branch.centerOfMass;
                    cm.x /= node.branch.mass;
                    cm.y /= node.branch.mass;
                },
            }

            return true;
        }

        fn visitNodeTraverse(node: *?*Node, position: Vec2, comptime callback: anytype, args: anytype) void {
            // const CBType = @TypeOf(callback);
            // const info = @typeInfo(CBType);
            const CBType = @TypeOf(callback);
            const info = @typeInfo(CBType);

            // if

            if (node.*) |n| {
                switch (n.*) {
                    .leaf => |leaf| {
                        // TODO: Move to Vec2
                        var p = position;
                        p.x += leaf.position.x;
                        p.y += leaf.position.y;
                        // TODO: Refactor callback invokation

                        if (info.Fn.return_type == void) {
                            callback(n, p, args);
                        } else {
                            if (!callback(n, p, args)) {
                                return;
                            }
                        }

                        // callback(n);
                        // comptime var isFn: bool = false;
                        // switch (info) {
                        //     .Fn => |f| {
                        //         for (f.params) |param| {
                        //             if (param.type.? == *Node) {
                        //                 callback(n);
                        //             }
                        //         }
                        //     },
                        //     else => @compileError("Callback should be a function or a null."),
                        // }
                    },
                    .branch => |branch| {
                        var p = position;
                        p.x += branch.centerOfMass.x;
                        p.y += branch.centerOfMass.y;

                        if (info.Fn.return_type == void) {
                            callback(n, p, args);
                        } else {
                            if (!callback(n, p, args)) {
                                return;
                            }
                        }

                        for (branch.children, 0..) |child, quadrant| {
                            var qPosition = n.where(@intCast(quadrant));
                            // std.debug.print("qPos: {?}", .{qPosition});
                            qPosition.x += position.x;
                            qPosition.y += position.y;

                            Self.visitNodeTraverse(@constCast(&child), qPosition, callback, args);
                        }
                    },
                }
            } else {}
        }
        fn cb(node: *Node, position: Vec2, _: anytype) void {
            switch (node.*) {
                .leaf => |leaf| {
                    _ = leaf; // autofix

                    std.debug.print("Leaf Position: {?} \n", .{position});
                },
                .branch => |branch| {
                    _ = branch; // autofix
                    std.debug.print("Branch Position: {?} \n", .{node.branch.mass});
                },
            }

            return;
        }

        pub fn traverse(self: Self) !void {
            if (!self.final) {
                return ErrorError.NotFinalized;
            }
            Self.visitNodeTraverse(@constCast(&self.root), .{}, cb, .{});
        }
        /// Takes callback which optionally returns boolean.
        pub fn traverseArgs(self: Self, comptime callback: anytype, args: anytype) !void {
            if (!self.final) {
                return ErrorError.NotFinalized;
            }
            Self.visitNodeTraverse(@constCast(&self.root), .{}, callback, args);
        }

        // TODO: Remove pointer to node from callback
    };
}
// TODO: Move in other module
const ErrorError = error{ Abc, NotFinalized, BodyAtGivenPositionAlreadyExist, PositionOutOfBound };

const tt = std.testing;

test "mass" {
    std.debug.print("New test starting\n", .{});
    // TODO
    var tr = try Tree().init(64);

    try tr.addBody(10, .{ .x = 0, .y = 0 });
    try tr.addBody(20, .{ .x = 9, .y = 9 });
    try tr.addBody(50, .{ .x = 19, .y = 12 });
    // try tr.print();
    try tt.expectEqual((10 + 20 + 50), tr.root.?.branch.mass);
    std.debug.print("Actual mass: {?}", .{tr.root.?.branch.mass});
    std.debug.print("Test is finished\n\n\n\n", .{});
}

test "center of mass" {
    // TODO
    var tr = try Tree().init(64);

    try tr.addBody(10, .{ .x = 0, .y = 7 });
    try tr.addBody(20, .{ .x = 9, .y = 15 });
    try tr.addBody(50, .{ .x = 19, .y = 12 });

    tr.finalize();

    try tr.print();
}

test "size" {
    // TODO
}

test "init tree, 2 bodies test" {
    // TODO
}

test "init tree with wrong size" {
    // Right sizes
    _ = try Tree().init(16);
    _ = try Tree().init(8);
    _ = try Tree().init(64);
    _ = try Tree().init(1024);

    // Wrong size
    // Cant test it, becauze it raises compile time error if size is wrong
    // In order to run tests, we need to compile first
    //
    // Uncomment next line to test if it fails to build

    // _ = try Tree().init(99);

    // You should get this error: Bad value, size should be a power of two.
}

test "add body with same position" {
    var tr = try Tree().init(64);

    try tr.addBody(11, .{ .x = 0, .y = 1 });
    try tr.addBody(12, .{ .x = 8, .y = 8 });
    try tr.addBody(13, .{ .x = 10, .y = 0 });
    try tr.addBody(14, .{ .x = 0, .y = 10 });

    var tr2 = try Tree().init(64);

    try tr2.addBody(11, .{ .x = 0, .y = 1 });
    try tr2.addBody(12, .{ .x = 8, .y = 8 });
    try tr2.addBody(13, .{ .x = 10, .y = 0 });
    try tr2.addBody(14, .{ .x = 0, .y = 10 });
    // Add the same body
    try tt.expectError(ErrorError.BodyAtGivenPositionAlreadyExist, tr2.addBody(14, .{ .x = 0, .y = 10 }));

    try tt.expectEqualDeep(tr, tr2);
}

test "traverse leafs and check positions" {
    var tr = try Tree().init(64);

    try tr.addBody(11, .{ .x = 0, .y = 1 });
    try tr.addBody(12, .{ .x = 8, .y = 8 });
    try tr.addBody(13, .{ .x = 10, .y = 0 });
    try tr.addBody(14, .{ .x = 0, .y = 10 });

    tr.finalize();
    // TODO: Do actual testing
    // Rn just watch the output and compare with values above
    try tr.traverse();
}
test "traverse without finalizing" {
    var tr = try Tree().init(64);
    try tt.expectError(ErrorError.NotFinalized, tr.traverse());
}

test "Add node outside the bound" {
    std.debug.print("New test starting\n", .{});
    var tr = try Tree().init(16);

    // Outside of 16
    try tt.expectError(ErrorError.Abc, tr.addBody(11, .{ .x = 0, .y = 22 }));
}
