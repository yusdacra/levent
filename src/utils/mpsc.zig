const std = @import("std");

const assert = std.debug.assert;
const cache_line = std.atomic.cache_line;
const AtomicUsize = std.atomic.Value(usize);
const Ordering = std.atomic.Ordering;
const Allocator = std.mem.Allocator;

// A modified version of Dmitry Vyukov's bounded MPMC queue,
// adapted for single-consumer usage:
// https://www.1024cores.net/home/lock-free-algorithms/queues/bounded-mpmc-queue
//
// Most notably, allowing only a single thread to receive at
// the same time greatly simplifies the dequeue logic and
// removes the need for some atomic operations.
//
// Taken from https://gist.github.com/vbe0201/2f30163415e6e99dafe3045d8d254b4f and updated

pub const TryPushError = error{CapacityReached};

/// A bounded MPSC queue storing `T` values.
pub fn Queue(comptime T: type) type {
    return struct {
        // Index into the buffer at which the next element
        // to enqueue should be placed.
        //
        // Must be masked with `buffer_mask`.
        enqueue_pos: AtomicUsize align(cache_line),

        // Index into the buffer from which the next element
        // should be obtained, if present.
        //
        // Must be masked with `buffer_mask`.
        dequeue_pos: usize align(cache_line),

        // A buffer of queue slots at which values can be
        // placed. A sequential stamp indicates if a slot
        // currently holds a value.
        slots: [*]Slot,

        // Bit mask for masking enqueue/dequeue positions
        // and advancing slot stamps after every usage.
        slots_mask: usize,

        // The allocator used to allocate the slot list.
        // Kept for later resource cleanup.
        alloc: Allocator,

        /// A Queue slot.
        const Slot = struct {
            sequence: AtomicUsize,
            value: T = undefined,
        };

        const Self = @This();

        /// Creates a new instance of the Queue with a given
        /// capacity.
        ///
        /// The `alloc` argument is used once to allocate
        /// `capacity` value slots. No subsequent allocations
        /// will ever happen.
        ///
        /// `.deinit()` must be called later to free the
        /// occupied resources.
        ///
        /// `capacity` must be at least 2 and a power of two.
        pub fn init(alloc: Allocator, capacity: usize) !Self {
            assert(capacity >= 2 and std.math.isPowerOfTwo(capacity));

            const slots = try alloc.alloc(Slot, capacity);
            var index: usize = 0;
            for (slots) |*slot| {
                slot.* = .{ .sequence = AtomicUsize.init(index) };
                index += 1;
            }

            return .{
                .enqueue_pos = AtomicUsize.init(0),
                .dequeue_pos = 0,
                .slots = slots.ptr,
                .slots_mask = capacity - 1,
                .alloc = alloc,
            };
        }

        /// Frees the resources occupied by this Queue.
        pub fn deinit(self: Self) void {
            self.alloc.free(self.slots[0..self.len()]);
        }

        /// Gets the capacity of the Queue, i.e. how many
        /// elements it can store at once.
        pub fn len(self: *const Self) usize {
            // We subtracted 1 from capacity during type
            // construction. Thus, this never overflows.
            return self.slots_mask + 1;
        }

        /// Attempts to push a value into the Queue, returning
        /// whether the operation was successful.
        pub fn tryPush(self: *Self, value: T) TryPushError!void {
            var pos = self.enqueue_pos.load(.monotonic);

            while (true) {
                const slot = &self.slots[pos & self.slots_mask];

                const cmp: isize = @bitCast(slot.sequence.load(.acquire) -% pos);
                if (cmp == 0) {
                    // Stamp value matches enqueue position;
                    // we can attempt to claim this slot.
                    if (self.enqueue_pos.cmpxchgStrong(pos, pos +% 1, .monotonic, .monotonic)) |old| {
                        pos = old;
                    } else {
                        // We claimed the slot, store our value.
                        slot.value = value;
                        slot.sequence.store(pos +% 1, .release);

                        return;
                    }
                } else if (cmp < 0) {
                    // Stamp value is smaller than enqueue position;
                    // slot is currently filled so we can't touch it.
                    return TryPushError.CapacityReached;
                } else {
                    // Stamp value is greater than enqueue position;
                    // we raced with another producer that has already
                    // claimed the slot so we need to retry.
                    pos = self.enqueue_pos.load(.monotonic);
                }
            }
        }

        /// Attempts to pop the next value off the queue.
        ///
        /// Returns `null` when the Queue does not store
        /// any elements currently.
        ///
        /// Only one concurrent caller allowed at any time!
        pub fn tryPop(self: *Self) ?T {
            var pos = self.dequeue_pos;
            const slot = &self.slots[pos & self.slots_mask];
            pos +%= 1;

            // If stamp is ahead of dequeue position by one,
            // we can take the value from the slot.
            const stamp = slot.sequence.load(.acquire);
            if (stamp == pos) {
                // Advance dequeue position to next slot.
                self.dequeue_pos = pos;

                // Advance the sequence count to mark the
                // slot as unoccupied.
                const value = slot.value;
                slot.sequence.store(pos +% self.slots_mask, .release);

                return value;
            } else {
                return null;
            }
        }
    };
}
