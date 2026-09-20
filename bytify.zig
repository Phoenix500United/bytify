const std = @import("std");
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const file = std.Io.File.stdin();
    const stdout = std.Io.File.stdout();

    const allocator = init.gpa;

    var buffer: [1024]u8 = undefined;
    var stdin = file.readerStreaming(io, &buffer);

    //Make these launch flags
    //Get input file
    try stdout.writeStreamingAll(io, "Input File: ");
    const i_path = try stdin.interface.takeDelimiter('\n');
    //remove \r
    const cwd = std.Io.Dir.cwd();
    const i_file = try cwd.openFile(io, i_path.?, .{});
    defer i_file.close(io);

    //Get output file
    try stdout.writeStreamingAll(io, "Output File: ");
    const o_path = try stdin.interface.takeDelimiter('\n');
    //remove \r
    const o_file = try cwd.createFile(io, o_path.?, .{});
    defer o_file.close(io);

    try stdout.writeStreamingAll(io, "Array Name: ");
    const array_name = try stdin.interface.takeDelimiter('\n');
    //remove \r

    //gets file stats
    const stat = try i_file.stat(io);
    const file_size = stat.size;

    //reads file data
    const i_file_buffer = try allocator.alloc(u8, file_size);
    defer allocator.free(i_file_buffer);

    var reader = i_file.readerStreaming(io, &.{});
    try reader.interface.readSliceAll(i_file_buffer);

    var output_unit = [_]u8{ '0', 'x', 'F', 'F', ',' };
    const lookup = [_]u8{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F' };
    const c_syntax_start = "const unsigned char ";
    const c_syntax_end = "[] = {";
    const c_syntax_finish = "};";

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
            output_unit[2] = lookup[i_file_buffer[index] & 0x0F];
            output_unit[3] = lookup[i_file_buffer[index] >> 4];
            @memcpy(output_sting_buffer[output_index .. output_index + 5], output_unit[0..5]);
            output_index += output_unit.len;
        }
        output_sting_buffer[output_index] = '\n';
        output_index += 1;
    }
    for (0..leftovers) |leftover| {
        const index = line_size * total_lines + leftover;
        output_unit[2] = lookup[i_file_buffer[index] & 0x0F];
        output_unit[3] = lookup[i_file_buffer[index] >> 4];
        @memcpy(output_sting_buffer[output_index .. output_index + 5], output_unit[0..5]);
        output_index += output_unit.len;
    }
    std.mem.copyForwards(u8, output_sting_buffer[output_index..], c_syntax_finish);

    try o_file.writeStreamingAll(io, output_sting_buffer);
}
