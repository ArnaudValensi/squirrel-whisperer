// Transcription via Groq's OpenAI-compatible Whisper endpoint — fully in-process
// using libcurl (JAI's Curl module), no subprocess. response_format=text returns
// the transcript as the raw body, so there's no JSON to parse on success.

GROQ_URL   :: "https://api.groq.com/openai/v1/audio/transcriptions";
GROQ_MODEL :: "whisper-large-v3";

transcribe :: (wav_path: string, api_key: string, lang_code: string) -> (text: string, ok: bool) {
    curl := curl_easy_init();
    if !curl {
        log_line("curl_easy_init failed");
        return "", false;
    }
    defer curl_easy_cleanup(curl);

    curl_easy_setopt(curl, .URL, temp_c_string(GROQ_URL));
    curl_easy_setopt(curl, .USERAGENT, "voiceinput");
    curl_easy_setopt(curl, .CONNECTTIMEOUT, 10);  // seconds to connect
    curl_easy_setopt(curl, .TIMEOUT, 20);         // seconds for the whole request

    auth := curl_slist_append(null, temp_c_string(tprint("Authorization: Bearer %", api_key)));
    defer curl_slist_free_all(auth);
    curl_easy_setopt(curl, .HTTPHEADER, auth);

    // multipart/form-data body
    mime := curl_mime_init(curl);
    defer curl_mime_free(mime);

    file_part := curl_mime_addpart(mime);
    curl_mime_name(file_part, "file");
    curl_mime_filedata(file_part, temp_c_string(wav_path));

    add_text_field(mime, "model",           GROQ_MODEL);
    add_text_field(mime, "language",         lang_code);
    add_text_field(mime, "response_format",  "text");

    curl_easy_setopt(curl, .MIMEPOST, mime);

    body: String_Builder;
    defer free_buffers(*body);
    curl_easy_setopt(curl, .WRITEFUNCTION, groq_write_cb);
    curl_easy_setopt(curl, .WRITEDATA, *body);

    code := curl_easy_perform(curl);
    if code != .OK {
        log_line(tprint("curl perform error: %", to_string(curl_easy_strerror(code))));
        return "", false;
    }

    http_code: int;
    curl_easy_getinfo(curl, .RESPONSE_CODE, *http_code);

    raw := builder_to_string(*body);
    defer free(raw);
    text := trim(raw);
    if http_code != 200 {
        log_line(tprint("Groq HTTP %: %", http_code, text));
        return "", false;
    }
    return copy_string(text), true;
}

add_text_field :: (mime: *curl_mime, name: string, value: string) {
    p := curl_mime_addpart(mime);
    curl_mime_name(p, temp_c_string(name));
    curl_mime_data(p, value.data, xx value.count);
}

groq_write_cb :: (ptr: *u8, size: u64, nmemb: u64, userdata: *void) -> u64 #c_call {
    b := cast(*String_Builder) userdata;
    push_context {
        append(b, ptr, xx nmemb);
    }
    return nmemb;
}
