// --------------------------------------------------------
// ZBody - Concurrent N-body sim using Barnes-Hut and Zig
// --------------------------------------------------------
// Codeberg: https://codeberg.org/pyranota/Z-body
// Licensed under the MIT License
// --------------------------------------------------------

const rl = @import("raylib");
const vec2 = @import("zb-core").vec2;

// Primitives
const Vec2F = vec2.Vec2F;
const Vector2 = rl.Vector2;

/// Convert zb-core's Vec2F to raylib's Vector2
pub fn @"Vec2F to Vector2"(vec2f: Vec2F) Vector2 {
    return Vector2.init(vec2f[0], vec2f[1]);
}

/// Convert raylib's Vector2 to zb-core's Vec2F
pub fn @"Vector2 to Vec2F"(vector2: Vector2) Vec2F {
    return .{ vector2.x, vector2.y };
}
