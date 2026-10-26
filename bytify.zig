const std = @import("std");
const FileUse = enum(u8) { INPUT, OUTPUT };
const InputFlag = enum(u8) { DEFAULT = 0b00, MUTABLE = 0b10, STRING = 0b01 };
const OutputFlag = enum(u8) { REMOVE = 0b01, C = 0b000, CPP = 0b010, ZIG = 0b100 };
const LANG_OPPERATOR: u8 = 0b110;
const File = struct { file: std.Io.File, size: u64 = 0, name: [128]u8 = undefined, name_len: usize = 0, flags: u8 = 0, use: FileUse };

fn isLetter(c: u8) bool {
    return (c >= 65 and c <= 90) or (c >= 96 and c <= 122);
}
fn isNumber(c: u8) bool {
    return (c >= 48 and c <= 57);
}

fn getStartSyntax(o: u8, i: u8) []const u8 {
    const lang_index: u8 = (o & LANG_OPPERATOR) >> 1;
    const mutable_index: u8 = i & @intFromEnum(InputFlag.MUTABLE);
    const lookup = [_][2][]const u8{
        .{ "const unsigned char ", "unsighed char" },
    };
    return lookup[lang_index][mutable_index];
}

fn getMiddleSyntax(o: u8) []const u8 {
    const lang_index: u8 = (o & LANG_OPPERATOR) >> 1;
    //I'll probably need input flag also for zig since I need to know mutable after name
    const lookup = [_][]const u8{"[] = {\n"};
    return lookup[lang_index];
}

fn getEndSyntax(o: u8) []const u8 {
    const lang_index: u8 = (o & LANG_OPPERATOR) >> 1;
    const lookup = [_][]const u8{"};\n\n"};

    return lookup[lang_index];
}

fn getSizeStartSyntax(o: u8, i: u8) []const u8 {
    const lang_index: u8 = (o & LANG_OPPERATOR) >> 1;
    const mutable_index: u8 = i & @intFromEnum(InputFlag.MUTABLE);
    const lookup = [_][2][]const u8{
        .{ "const unsigned ", "unsighed " },
    };
    return lookup[lang_index][mutable_index];
}

fn getSizeMiddleSyntax(o: u8) []const u8 {
    const lang_index: u8 = (o & LANG_OPPERATOR) >> 1;
    //I'll probably need input flag also for zig since I need to know mutable after name
    const lookup = [_][]const u8{"_size = "};
    return lookup[lang_index];
}

fn getSizeEndSyntax(o: u8) []const u8 {
    const lang_index: u8 = (o & LANG_OPPERATOR) >> 1;
    const lookup = [_][]const u8{";\n\n"};

    return lookup[lang_index];
}

fn getOutput(io: std.Io, cwd: std.Io.Dir, writer: *std.Io.Writer, path: []const u8, flags: u8) !?File {
    const output = (if (flags & @intFromEnum(OutputFlag.REMOVE) != @intFromEnum(OutputFlag.REMOVE))
        cwd.createFile(io, path, .{ .exclusive = true })
    else
        cwd.createFile(io, path, .{ .truncate = false })) catch |err| switch (err) {
        error.FileNotFound => {
            try writer.print("{s}, Invalid Directory \n", .{path});
            return null;
        },
        error.AccessDenied => {
            try writer.print("{s}, permission denied\n", .{path});
            return null;
        },
        error.PathAlreadyExists => {
            try writer.print("{s}, overwrite denied use -or\n", .{path});
            return null;
        },
        else => return err,
    };

    const f: File = .{ .file = output, .use = FileUse.OUTPUT, .flags = flags, .name_len = 0, .size = 0 };
    return f;
}

fn getInput(io: std.Io, cwd: std.Io.Dir, writer: *std.Io.Writer, path: []const u8, name: ?[]const u8, flags: u8) !?File {
    const input = cwd.openFile(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            try writer.print("{s}, File not found\n", .{path});
            return null;
        },
        error.AccessDenied => {
            try writer.print("{s}, permission denied\n", .{path});
            return null;
        },
        else => return err,
    };

    const stat = try input.stat(io);
    const size = stat.size;
    if (size > std.math.maxInt(u32)) {
        try writer.print("{s}, File exceeds maximum size\n", .{path});
        return null;
    }

    const array_name: []const u8 = if (name) |n| n else blk: {
        const last_slash = std.mem.lastIndexOfScalar(u8, path, '/') orelse {
            break :blk path;
        };
        break :blk path[last_slash + 1 ..];
    };

    const len = @min(array_name.len, 128);
    var f: File = .{ .name_len = len, .flags = flags, .file = input, .size = size, .use = FileUse.INPUT };
    @memcpy(f.name[0..len], array_name[0..len]);

    if (name == null) {
        if (!(isLetter(f.name[0]) or f.name[0] == '_')) {
            f.name[0] = '_';
        }

        for (1..len) |i| {
            const c = f.name[i];
            if (!(isLetter(c) or isNumber(c) or c == '_')) {
                f.name[i] = '_';
            }
        }
    }

    return f;
}

fn getDigitCount(number: u64) u64 {
    var digits: u64 = 1;
    var n = number;
    while (n >= 10) {
        digits += 1;
        n /= 10;
    }
    return digits;
}

fn updateOutput(output: *File, input: *const File, output_unit: []const u8, line_size: u8) void {
    const is_string: bool = @as(InputFlag, @enumFromInt(input.flags & @intFromEnum(InputFlag.STRING))) == InputFlag.STRING;
    switch (output.flags & LANG_OPPERATOR) {
        @intFromEnum(OutputFlag.C) => {
            var file_size = input.size;

            if (is_string) {
                file_size = file_size + 1;
            }
            output.size += input.name_len + getStartSyntax(output.flags, input.flags).len + getMiddleSyntax(output.flags).len + getEndSyntax(output.flags).len;
            output.size += input.name_len + getSizeStartSyntax(output.flags, input.flags).len + getSizeMiddleSyntax(output.flags).len + getSizeEndSyntax(output.flags).len + getDigitCount(file_size);

            const total_lines = file_size / @as(u64, line_size);
            const leftover_count = file_size % @as(u64, line_size);
            if (leftover_count > 0) {
                output.size += 1;
            }
            output.size += @as(u64, output_unit.len) * file_size + total_lines;
        },
        @intFromEnum(OutputFlag.CPP) => {
            //TBA use constexpr/constinit, std::array and std::string,
        },
        @intFromEnum(OutputFlag.ZIG) => {
            //TBA probably not needed since you can load stuff into exe at compile time but this is made in zig so it feels off not to include it
        },
        else => {},
    }
}
fn close_files(io: std.Io, files: std.ArrayListUnmanaged(File)) void {
    for (files.items) |*f| {
        f.file.close(io);
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const stdout = std.Io.File.stdout();

    const allocator = init.gpa;
    const arena_allocator = init.arena;
    const args = try init.minimal.args.toSlice(arena_allocator.allocator());

    if (args.len == 0) {
        try stdout.writeStreamingAll(io, "NO ARGS PROVIDED\n");
        return;
    }

    var index: usize = 1;
    const cwd = std.Io.Dir.cwd();
    var files: std.ArrayListUnmanaged(File) = .{ .items = &.{}, .capacity = 0 };
    defer close_files(io, files);
    try files.ensureTotalCapacity(arena_allocator.allocator(), 10);

    var output_index: usize = 0;

    var output_unit = [_]u8{ '0', 'x', 'F', 'F', ',' };
    const newline_output = [_]u8{ '0', 'x', '0', '0', ',' };

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = stdout.writer(io, &stdout_buffer);
    const writer: *std.Io.Writer = &stdout_writer.interface;

    var largest_output_size: u64 = 0;
    var largest_input_size: u64 = 0;

    if (args.len < 2) {
        //no inputs
        return;
    }
    while (index < args.len) {
        const arg = args[index];
        if (arg[0] == '-') {
            switch (arg[1]) {
                'i' => {
                    if (files.items.len == 0) {
                        //error
                    }
                    var flag: u8 = 0;
                    if (arg.len > 2) {
                        if (arg.len > 4) {} //can only have 2 flags atm
                        for (arg[2..arg.len]) |c| {
                            switch (c) {
                                'm' => {
                                    const flag_value: u8 = @intFromEnum(InputFlag.MUTABLE);
                                    if (flag & flag_value == flag_value) {
                                        //error
                                        return;
                                    } else {
                                        flag = flag | flag_value;
                                    }
                                },
                                's' => {
                                    const flag_value: u8 = @intFromEnum(InputFlag.STRING);
                                    if (flag & flag_value == flag_value) {
                                        //error
                                        return;
                                    } else {
                                        flag = flag | flag_value;
                                    }
                                },
                                else => {
                                    //error
                                    return;
                                },
                            }
                        }
                    }

                    var index_increase_amount: usize = 2;
                    const input_file = (if (!(index + 2 < args.len) or args[index + 2][0] == '-')
                        try getInput(io, cwd, writer, args[index + 1], null, flag)
                    else blk: {
                        index_increase_amount += 1;
                        break :blk try getInput(io, cwd, writer, args[index + 1], args[index + 2], flag);
                    }) orelse {
                        try writer.flush();
                        return;
                    };

                    updateOutput(&(files.items[output_index]), &input_file, &output_unit, 10);
                    try files.append(arena_allocator.allocator(), input_file);
                    largest_input_size = if (files.getLast().size > largest_input_size) files.getLast().size else largest_input_size;

                    index += index_increase_amount;
                },
                'o' => {
                    //output initilization code
                    const lang_map = std.StaticStringMap(u8).initComptime(.{ .{ "c", @intFromEnum(OutputFlag.C) }, .{ "zig", @intFromEnum(OutputFlag.ZIG) }, .{ "c++", @intFromEnum(OutputFlag.CPP) } });

                    var flag: u8 = 0;
                    if (arg.len > 2) {
                        if (arg.len == 3 and arg[2] == 'r') {
                            flag = flag | @intFromEnum(OutputFlag.REMOVE);
                        } else {
                            //invalid output flag error
                            return;
                        }
                    }

                    var index_increase_amount: usize = 2;

                    const output_file = (if (index + 2 < args.len and args[index + 2][0] == '-')
                        try getOutput(io, cwd, writer, args[index + 1], flag)
                    else blk: {
                        index_increase_amount += 1;
                        const lang: u8 = lang_map.get(args[index + 2]) orelse {
                            try writer.print("{s}, Invalid Langauge", .{args[index + 2]});
                            try writer.flush();
                            return;
                        };
                        flag = flag & lang;
                        break :blk try getOutput(io, cwd, writer, args[index + 1], flag);
                    }) orelse {
                        try writer.flush();
                        return;
                    };
                    if (files.items.len > 0) {
                        largest_output_size = if (files.items[output_index].size > largest_output_size) files.items[output_index].size else largest_output_size;
                        output_index += 1;
                    }

                    try files.append(arena_allocator.allocator(), output_file);
                    index += index_increase_amount;
                },
                else => {},
            }
        } else {
            if (arg[0] == 'i' or arg[0] == 'o' and arg.len == 1) {
                try writer.print("{s}, Invalid arg, expected -{s}\n", .{ args[index], args[index] });
                try writer.flush();
                return;
            } else {
                try writer.print("{s}, Invalid arg\n", .{args[index]});
                try writer.flush();
                return;
            }
        }
    }

    largest_output_size = if (files.items[output_index].size > largest_output_size) files.items[output_index].size else largest_output_size;

    const output_buffer: []u8 = try allocator.alloc(u8, largest_output_size);
    defer allocator.free(output_buffer);
    const input_buffer: []u8 = try allocator.alloc(u8, largest_input_size);
    defer allocator.free(input_buffer);

    var active_output: ?*File = null;
    var o_index: usize = 0;

    const lookup = [_]u8{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F' };

    for (files.items) |*f| {
        if (f.use == FileUse.INPUT) {
            const output = active_output.?;
            var buffer = getStartSyntax(output.flags, f.flags);
            _ = try f.file.readPositionalAll(io, input_buffer[0..@intCast(f.size)], 0);
            std.mem.copyForwards(u8, output_buffer[o_index..], buffer);
            o_index += buffer.len;
            std.mem.copyForwards(u8, output_buffer[o_index..], f.name[0..f.name_len]);
            o_index += f.name_len;
            buffer = getMiddleSyntax(output.flags);
            std.mem.copyForwards(u8, output_buffer[o_index..], buffer);
            o_index += buffer.len;

            const line_size = 10;
            const line_count = f.size / line_size;
            const leftovers = f.size % line_size;

            for (0..line_count) |line| {
                for (0..line_size) |line_index| {
                    const input_index = line * line_size + line_index;
                    output_unit[2] = lookup[input_buffer[input_index] >> 4];
                    output_unit[3] = lookup[input_buffer[input_index] & 0x0F];
                    @memcpy(output_buffer[o_index .. o_index + 5], output_unit[0..5]);
                    o_index += output_unit.len;
                }
                output_buffer[o_index] = '\n';
                o_index += 1;
            }

            for (0..leftovers) |leftover| {
                const input_index = line_size * line_count + leftover;
                output_unit[2] = lookup[input_buffer[input_index] >> 4];
                output_unit[3] = lookup[input_buffer[input_index] & 0x0F];

                @memcpy(output_buffer[o_index .. o_index + 5], output_unit[0..5]);
                o_index += output_unit.len;
            }
            if (f.flags & @intFromEnum(InputFlag.STRING) == @intFromEnum(InputFlag.STRING)) {
                @memcpy(output_buffer[o_index .. o_index + 5], newline_output[0..5]);
                o_index += newline_output.len;
            }
            if (leftovers > 0) {
                output_buffer[o_index] = '\n';
                o_index += 1;
            }
            buffer = getEndSyntax(output.flags);
            std.mem.copyForwards(u8, output_buffer[o_index..], buffer);
            o_index += buffer.len;
            buffer = getSizeStartSyntax(output.flags, f.flags);
            std.mem.copyForwards(u8, output_buffer[o_index..], buffer);
            o_index += buffer.len;
            std.mem.copyForwards(u8, output_buffer[o_index..], f.name[0..f.name_len]);
            o_index += f.name_len;
            buffer = getSizeMiddleSyntax(output.flags);
            std.mem.copyForwards(u8, output_buffer[o_index..], buffer);
            o_index += buffer.len;
            const number_str = try std.fmt.bufPrint(output_buffer[o_index..], "{d}", .{f.size + @as(u64, @intCast(f.flags & @intFromEnum(InputFlag.STRING)))});
            o_index += number_str.len;
            buffer = getSizeEndSyntax(output.flags);
            std.mem.copyForwards(u8, output_buffer[o_index..], buffer);
            o_index += buffer.len;
        } else {
            if (active_output != null) {
                try active_output.?.file.writeStreamingAll(io, output_buffer[0..@intCast(active_output.?.size)]);
                if (active_output.?.flags & @intFromEnum(OutputFlag.REMOVE) == @intFromEnum(OutputFlag.REMOVE)) {
                    try active_output.?.file.setLength(io, o_index);
                }
            }
            active_output = f;
            o_index = 0;
        }
    }
    try active_output.?.file.writeStreamingAll(io, output_buffer[0..@intCast(active_output.?.size)]);
    if (active_output.?.flags & @intFromEnum(OutputFlag.REMOVE) == @intFromEnum(OutputFlag.REMOVE)) {
        try active_output.?.file.setLength(io, o_index);
    }
}
