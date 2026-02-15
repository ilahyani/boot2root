# WRITEUP 2

Dirty COW (CVE-2016-5195) is a Linux kernel local privilege escalation vulnerability caused by a race condition in the Copy-On-Write (COW) memory mechanism, present since kernel 2.6.22 (2007) and patched in October 2016. The vulnerability allows a local user to overwrite read-only files by exploiting a race between memory invalidation and write operations. The exploit works by mapping a protected file such as `/etc/passwd` into memory using `mmap()` (read-only mapping), repeatedly calling `madvise(MADV_DONTNEED)` to force the kernel to discard cached pages, and concurrently writing to the mapped memory in a separate thread. Due to the race condition, the kernel may incorrectly apply the write to the underlying file, effectively bypassing read-only protections.

### Exploitation Steps

1. **Download and transfer the exploit**
   Run the script (`downld_exploit.sh`) to download the exploit using `curl` and copy it to the machine using `scp`.

2. **SSH into the machine**

   ```bash
   ssh laurie@192.168.56.3
   ```

3. **Compile the exploit**

   ```bash
   gcc -pthread dirty.c -o dirty -lcrypt
   ```

   * `-pthread` enables multithreading for triggering the race condition.
   * `-lcrypt` is required for password hashing when modifying `/etc/passwd`.

4. **Execute the exploit**

   ```bash
   ./dirty
   ```

   When prompted, enter a new password. The exploit backs up `/etc/passwd`, injects a new user entry with UID 0 (root privileges), and applies the chosen password hash.

5. **Verify privilege escalation**

   ```bash
   su <new_user>
   id
   ```

   If successful, the user will have root gid (0).

This demonstrates how Dirty COW leverages a kernel-level race condition to escalate from a standard user account to full root access on unpatched systems.
