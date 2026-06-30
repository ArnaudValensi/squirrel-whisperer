// Memory model: "allocate by lifetime, reclaim by batch" (see oob-jai memory.md).
//
// Two tiers:
//   - Event:      temporary storage, reclaimed in one shot at the end of each
//                 event handler (a recording, a menu action). temp_scope() routes
//                 the handler's transient allocations there and resets after.
//   - Persistent: the default allocator, for app-lifetime data. Globals are
//                 reachable, so the leak debugger counts them as non-leak.

// Open a per-event scope and reclaim everything at the end:
//   - Jai transient allocations go to temporary storage (reset on exit);
//   - Objective-C autoreleased objects (e.g. nss() strings) go to a fresh
//     NSAutoreleasePool that is drained on exit.
// Use at the top of each Objective-C event handler.
temp_scope :: () #expand {
    saved := context.allocator;
    context.allocator = temporary_allocator;
    pool := objc_init(objc_alloc(NSAutoreleasePool));
    `defer {
        NSAutoreleasePool.drain(pool);
        context.allocator = saved;
        reset_temporary_storage();
    }
}

// Replace an app-lifetime string global: free the previous copy and store a fresh
// one on the default allocator, so it survives the per-event temp reset. Pass the
// value freely (it may live in temp); we copy it out to the persistent allocator.
set_persistent_string :: (dst: *string, value: string) {
    if dst.data  free(dst.data,, context.default_allocator);
    dst.* = copy_string(value,, context.default_allocator);
}
