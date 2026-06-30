// Appends timestamped lines to ~/.cache/voice_input.log (and echoes to stdout).

log_path :: () -> string {
    return tprint("%/.cache/voice_input.log", home_dir());
}

log_line :: (msg: string) {
    line := tprint("%\n", msg);
    print("%", line);  // visible when launched from a terminal

    path := log_path();
    make_directory_if_it_does_not_exist(tprint("%/.cache", home_dir()), recursive=true);

    file, ok := file_open(path, for_writing=true, keep_existing_content=true);
    if !ok return;
    file_seek(file, 0, .END);
    file_write(*file, line);
    file_close(*file);
}
