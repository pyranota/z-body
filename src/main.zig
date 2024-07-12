const std = @import("std");
const mach = @import("mach");

// The global list of Mach modules registered for use in our application.
pub const modules = .{
    mach.Core,
    @import("App.zig"),
};

pub fn main() !void {
    // Initialize mach.Core
    try mach.core.initModule();

    std.debug.print("Hello", .{});
    // Main loop
    while (try mach.core.tick()) {}
}
