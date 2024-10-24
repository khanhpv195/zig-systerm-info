pub const packages = struct {
    pub const @"122013a875bae8cbae4fe55497217508c7cb7f439dcd1c2dd9d69379feb9e56e476d" = struct {
        pub const build_root = "/Users/black/.cache/zig/p/122013a875bae8cbae4fe55497217508c7cb7f439dcd1c2dd9d69379feb9e56e476d";
        pub const build_zig = @import("122013a875bae8cbae4fe55497217508c7cb7f439dcd1c2dd9d69379feb9e56e476d");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "zbench", "12203dc859d8fb1285544fa160bc0136d300757ca37ee4d5b4e7a0c6519048d26eec" },
        };
    };
    pub const @"12203dc859d8fb1285544fa160bc0136d300757ca37ee4d5b4e7a0c6519048d26eec" = struct {
        pub const build_root = "/Users/black/.cache/zig/p/12203dc859d8fb1285544fa160bc0136d300757ca37ee4d5b4e7a0c6519048d26eec";
        pub const build_zig = @import("12203dc859d8fb1285544fa160bc0136d300757ca37ee4d5b4e7a0c6519048d26eec");
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "zbench", "12203dc859d8fb1285544fa160bc0136d300757ca37ee4d5b4e7a0c6519048d26eec" },
    .{ "cpu-info", "122013a875bae8cbae4fe55497217508c7cb7f439dcd1c2dd9d69379feb9e56e476d" },
};
