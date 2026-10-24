const std = @import("std");
const FileUse = enum(u8) { INPUT, OUTPUT };
const InputFlag = enum(u8) { DEFAULT = 0b00, MUTABLE = 0b01, STRING = 0b10 };
const OutputFlag = enum(u8) { REMOVE = 0b01, C = 0b000, CPP = 0b010, ZIG = 0b100 };
const LANG_OPPERATOR: u8 = 0b110;
const File = struct { file: std.fs.File, size: u64, name: u8[128], name_len: usize, flags: u8, use: FileUse };

fn isLetter(c: u8) bool {
    return (c >= 65 and c <= 90) or (c >= 96 and c <= 122);
}
fn isNumber(c: u8) bool {
    return (c >= 48 and c <= 57);
}

fn getStartSyntax(o: *OutputFlag, i: *InputFlag) []const u8 {
    const lang_index: u8 = (@intFromEnum(o.flag) & LANG_OPPERATOR) >> 1;
    const mutable_index: u8 = @intFromEnum(i.flag) & 0b01;
    const lookup = [_][2][]const u8{
        .{ "const unsigned char ", "unsighed char" },
    };
    return lookup[lang_index][mutable_index];
}

fn getMiddleSyntax(o: *OutputFlag) []const u8 {
    const lang_index: u8 = (@intFromEnum(o.flag) & LANG_OPPERATOR) >> 1;
    //I'll probably need input flag also for zig since I need to know mutable after name
    const lookup = [_][]const u8{"[] = {\n"};
    return lookup[lang_index];
}

fn getEndSyntax(o: *OutputFlag) []const u8 {
    const lang_index: u8 = (@intFromEnum(o.flag) & LANG_OPPERATOR) >> 1;
    const lookup = [_][]const u8{"};\n\n"};

    return lookup[lang_index];
}

fn getSizeStartSyntax(o: *OutputFlag, i: *InputFlag) []const u8 {
    const lang_index: u8 = (@intFromEnum(o.flag) & LANG_OPPERATOR) >> 1;
    const mutable_index: u8 = @intFromEnum(i.flag) & 0b01;
    const lookup = [_][2][]const u8{
        .{ "const unsigned", "unsighed" },
    };
    return lookup[lang_index][mutable_index];
}

fn getSizeMiddleSyntax(o: *OutputFlag) []const u8 {
    const lang_index: u8 = (@intFromEnum(o.flag) & LANG_OPPERATOR) >> 1;
    //I'll probably need input flag also for zig since I need to know mutable after name
    const lookup = [_][]const u8{" = "};
    return lookup[lang_index];
}

fn getSizeEndSyntax(o: *OutputFlag) []const u8 {
    const lang_index: u8 = (@intFromEnum(o.flag) & LANG_OPPERATOR) >> 1;
    const lookup = [_][]const u8{";\n\n"};

    return lookup[lang_index];
}

fn getOutput(io: std.Io, cwd: std.fs.Dir, writer: *std.Io.Writer, path: []const u8, flags: u8) ?File {
    var fail: bool = false;
    var f: File = .{ .use = FileUse.OUTPUT, .flags = flags, .name_len = 0, .size = 0 };
    if (flags & @intFromEnum(OutputFlag.REMOVE) != @intFromEnum(OutputFlag.REMOVE)) {
        f.file = try cwd.createFile(io, path, .{ .exclusive = true }) catch |err| switch (err) {
            error.FileNotFound => {
                try writer.print(io, "{s}, Invalid Directory \n", .{path});
                fail = true;
            },
            error.AccessDenied => {
                try writer.print(io, "{s}, permission denied\n", .{path});
                fail = true;
            },
            error.PathAlreadyExist => {
                fail = true;
                try writer.print(io, "{s}, overwrite denied use -or", .{path});
            },
            else => return err,
        };
    } else {
        f.file = try cwd.createFile(io, path, .{ .truncate = false }) catch |err| switch (err) {
            error.FileNotFound => {
                try writer.print(io, "{s}, Invalid Directory \n", .{path});
                fail = true;
            },
            error.AccessDenied => {
                try writer.print(io, "{s}, permission denied\n", .{path});
                fail = true;
            },
        };
    }
    if (fail) {
        return null;
    }

    return f;
}

fn getInput(io: std.Io, cwd: std.fs.Dir, writer: *std.Io.Writer, path: []const u8, name: ?[]const u8, flags: u8) ?File {
    var fail: bool = false;
    const input = try cwd.openFile(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            try writer.print(io, "{s}, File not found\n", .{path});
            fail = true;
        },
        error.AccessDenied => {
            try writer.print(io, "{s}, permission denied\n", .{path});
            fail = true;
        },
        else => return err,
    };
    if (fail) {
        return null;
    }

    const size = try input.getEndPos();
    if (size > std.math.maxInt(u32)) {
        writer.print("{s}, File exceeds maximum size\n", path);
        return null;
    }

    const array_name: []const u8 = if (name) |n| n else blk: {
        var temp_name: []u8 = tmp: {
            const last_slash = std.mem.lastIndexOfScalar(u8, path, '/') orelse {
                break :tmp path;
            };
            break :tmp path[last_slash + 1 ..];
        };

        if (!(isLetter(temp_name[0] or temp_name[0] == '_'))) {
            temp_name[0] = '_';
        }

        for (1..temp_name.len) |i| {
            const c = temp_name[i];
            if (!(isLetter(c) or isNumber(c) or c == '_')) {
                temp_name[i] = '_';
            }
        }

        break :blk temp_name;
    };

    var f: File = .{};
    f.file = input;

    const len = @min(array_name.len, 128);
    @memcpy(f.name[0..len], array_name[0..len]);
    f.name_len = len;
    f.flags = flags;
    f.size = size;
    f.use = FileUse.INPUT;

    return f;
}
fn getDigitCount(number: u64) u8 {
    var digits: u8 = 1;
    while (number > 10) {
        digits += 1;
        number /= 10;
    }
    return digits;
}

fn updateOutput(output: *File, input: *File, output_unit: []const u8, line_size: u8) void {
    const is_string: bool = @as(InputFlag, @enumFromInt(input.flags & @intFromEnum(InputFlag.STRING))) == InputFlag.STRING;
    switch (output.flags & LANG_OPPERATOR) {
        @intFromEnum(OutputFlag.C) => {
            var file_size = input.size;
            if (is_string) {
                //rn just adds a null terminator might make a version that actually actually uses "" syntax and newlines on newlines
                //I think id need a way to add that and regular null terminated byte syntax tho
                file_size = file_size + 1;
            }

            output.size += input.name_len + getStartSyntax(output, input).len + getMiddleSyntax(output, input).len + getEndSyntax(output, input).len;
            output.size += input.name_len + 4 + getSizeStartSyntax(output, input).len + getSizeMiddleSyntax(output, input).len + getEndSyntax(output, input).len + getDigitCount(file_size);

            const total_lines = file_size / @as(u64, line_size);
            output.size += @as(u64, output_unit.len) * file_size + total_lines + 1;
        },
        @intFromEnum(OutputFlag.CPP) => {
            //TBA use constexpr/constinit, std::array and std::string,
        },
        @intFromEnum(OutputFlag.ZIG) => {
            //TBA probably not needed since you can load stuff into exe at compile time but this is made in zig so it feels off not to include it
        },
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const file = std.Io.File.stdin();
    const stdout = std.Io.File.stdout();

    const allocator = init.gpa;
    const arena_allocator = init.arena;
    const args = try init.minimal.args.toSlice(arena_allocator);

    const flag_enum = enum { string, c_cpp };

    const flags = std.StaticStringMap(flag_enum).initComptime(.{
        .{ "string", .string },
        .{ "c_c++", .c_cpp },
    });

    if (args.len == 0) {
        try stdout.writeStreamingAll(io, "NO ARGS PROVIDED\n");
        return;
    }
    var string = false;
    var args_processed = false;
    var langauge: ?flag_enum = null;
    var index: usize = 0;
    var buffer_size: usize = 0;
    const cwd = std.Io.Dir.cwd();
    var files: std.ArrayListUnmanaged(File) = .{};
    try files.ensureTotalCapacity(arena_allocator, 10);

    var output_index: ?usize = null;

    var output_unit = [_]u8{ '0', 'x', 'F', 'F', ',' };

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = stdout.writer(io, &stdout_buffer);
    const writer: *std.Io.Writer = &stdout_writer.interface;

    var largest_output_size: u64 = 0;
    var largest_input_size: u64 = 0;

    while (!args_processed) {
        const arg = args[index];
        if (arg[0] == '-') {
            switch (arg[1]) {
                'i' => {
                    if (output_index == null) {
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
                            }
                        }
                    }
                    var input_file: ?File = .{};
                    var index_increase_amount: usize = 1;
                    if (args[index + 2][0] == '-') {
                        input_file = getInput(io, cwd, writer, args[index + 1], null, flag);
                        if (input_file == null) {
                            return;
                        }
                        index_increase_amount = index_increase_amount + 1;
                    } else {
                        input_file = getInput(io, cwd, writer, args[index + 1], args[index + 2], flag);
                        if (input_file == null) {
                            return;
                        }
                    }
                    updateOutput(&files[output_index], input_file, output_unit, 10);
                    files.append(arena_allocator, input_file);
                    defer files.getLast().file.close(io);

                    output_index += index_increase_amount;
                },
                'o' => {
                    //output initilization code

                    if (output_index == null) {
                        output_index = 0;
                    } else {
                        largest_output_size = if (files[output_index].size > largest_output_size) files[output_index].size else largest_output_size;
                        output_index += 1;
                    }
                },
                else => {},
            }
        } else {
            if (arg[0] == 'i' or arg[0] == 'o' and arg.len == 1) {
                try stdout.print(io, "{s}, Invalid arg, expected -{s}\n", .{ args[index], args[index] });
                return;
            } else {
                try stdout.print(io, "{s}, Invalid arg\n", .{args[index]});
                return;
            }
        }
    }

    largest_output_size = if (files.getLast().size() > largest_output_size) files.getLast().size() else largest_output_size;

    const output_buffer: []u8 = allocator.alloc(u8, largest_output_size);
    defer allocator.free(output_buffer);
    const input_buffer: []u8 = allocator.alloc(u8, largest_input_size);
    defer allocator.free(input_buffer);

    var active_output: *File = null;
    var first_file: bool = true;

    for (files) |f| {
        if (f.use == FileUse.INPUT) {} else {
            if (active_output != null) {
                active_output.file.writeStreamingAll(io, output_buffer[0..active_output.size]);
            }
            active_output = &f;
        }
    }
    //gets file stats
    const stat = try i_file.stat(io);
    const file_size = stat.size;

    //reads file data
    const i_file_buffer = try allocator.alloc(u8, file_size);
    defer allocator.free(i_file_buffer);

    var reader = i_file.readerStreaming(io, &.{});
    try reader.interface.readSliceAll(i_file_buffer);

    const line_size: u8 = 10;
    const total_lines: u64 = file_size / line_size;
    const leftovers: u64 = file_size % line_size;

    const output_sting_buffer = try allocator.alloc(u8, file_size * output_unit.len +
        total_lines + c_syntax_start.len +
        c_syntax_end.len + c_syntax_finish.len +
        array_name.?.len);
    defer allocator.free(output_sting_buffer);

    var output_index: usize = 0;
    std.mem.copyForwards(u8, output_sting_buffer[output_index..], c_syntax_start);
    output_index += c_syntax_start.len;
    std.mem.copyForwards(u8, output_sting_buffer[output_index..], array_name.?);
    output_index += array_name.?.len;
    std.mem.copyForwards(u8, output_sting_buffer[output_index..], c_syntax_end);
    output_index += c_syntax_end.len;

    //c_syntax_start.len + array_name.?.len + c_syntax_end.len;
    for (0..total_lines) |line| {
        for (0..line_size) |line_index| {
            const index = line * line_size + line_index;
            output_unit[2] = lookup[i_file_buffer[index] >> 4];
            output_unit[3] = lookup[i_file_buffer[index] & 0x0F];
            @memcpy(output_sting_buffer[output_index .. output_index + 5], output_unit[0..5]);
            output_index += output_unit.len;
        }
        output_sting_buffer[output_index] = '\n';
        output_index += 1;
    }
    for (0..leftovers) |leftover| {
        const index = line_size * total_lines + leftover;
        output_unit[2] = lookup[i_file_buffer[index] >> 4];
        output_unit[3] = lookup[i_file_buffer[index] & 0x0F];

        @memcpy(output_sting_buffer[output_index .. output_index + 5], output_unit[0..5]);
        output_index += output_unit.len;
    }
    std.mem.copyForwards(u8, output_sting_buffer[output_index..], c_syntax_finish);

    try o_file.writeStreamingAll(io, output_sting_buffer);
}
