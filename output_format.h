const unsigned char format_test[] = {
//0xFF, < goes here
}; //Base cost array = name_len + 28 bytes + 2 (\n)

const unsigned format_test_size = 0; //Base cost size identifyer = name_len + 24 + log(number) + 1 + 1 (\n)
//output unit = 0xFF,  5 bytes

//total size = input_bytes * output_unit + 1(\n) * number_of_lines + Base cost array + base cost size identifyer + 2(\n) between arrays
