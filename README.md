# Autobot Army

ระบบรัน AI แบบอัตโนมัติ (Multi-Agent Loop) รวมพลัง AI 3 ตัวช่วยกันเขียนและตรวจโค้ดจนกว่าจะผ่าน:
1. **Claude (Reviewer)** - อ่านโค้ดและ diff เพื่อหาจุดผิดพลาดหรือช่องโหว่ แล้วเขียนรายงาน
2. **AGY (Developer)** - อ่านรายงานแล้วลงมือแก้ไขโค้ดจริง
3. **Codex (QA / Pentest)** - ทดสอบโค้ดและตรวจหาช่องโหว่ ถ้าผ่าน (`STATUS: PASS`) จะจบงานและ Commit โค้ดให้ทันที

---

## สิ่งที่ต้องติดตั้งก่อนเริ่มใช้งาน (Prerequisites)

เครื่องของคุณต้องติดตั้งโปรแกรมและ CLI เหล่านี้ไว้ในระบบ:
- [Git](https://git-scm.com/)
- `claude` (Claude CLI)
- `agy` (Antigravity CLI)
- `codex` (Codex CLI)

---

## การเปิด Permission (ทำครั้งแรกครั้งเดียว)

### สำหรับ Windows
เปิด **PowerShell** แล้วรันคำสั่งนี้ เพื่ออนุญาตให้เครื่องรันไฟล์ `.ps1` ได้:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### สำหรับ macOS / Linux
เปิด **Terminal** เข้ามาที่โฟลเดอร์นี้ แล้วรันคำสั่งนี้เพื่อให้สิทธิ์รันไฟล์ `.sh`:
```bash
chmod +x agent-loop.sh
```

---

## วิธีการใช้งาน

### 1. บน Windows (ใช้ `agent-loop.ps1`)

เปิด PowerShell แล้วรันคำสั่งตามรูปแบบนี้:

```powershell
.\agent-loop.ps1 -TargetDir "โฟลเดอร์โปรเจกต์" -Task "คำสั่งที่ต้องการให้ทำ" [-MaxRounds จำนวนรอบสูงสุด]
```

**ตัวอย่างการใช้งาน:**
```powershell
# ตัวอย่าง: สั่งให้แก้บั๊กหน้า Login (รอบ default สูงสุด 8 รอบ)
.\agent-loop.ps1 -TargetDir "C:\projects\my-app" -Task "Fix login token expiration bug and add tests"

# ตัวอย่าง: สั่งทำ Pentest ตรวจความปลอดภัย (จำกัดไม่เกิน 5 รอบ)
.\agent-loop.ps1 -TargetDir "C:\projects\my-app" -Task "Audit security for OWASP Top 10 and patch vulnerabilities" -MaxRounds 5

# ตัวอย่าง: สั่งรันต่อจาก Task ล่าสุดที่ยังไม่จบ (เพิ่มอีก 5 รอบ หรือตาม default 8 รอบ)
.\agent-loop.ps1 -TargetDir "C:\projects\my-app" -Resume
.\agent-loop.ps1 -TargetDir "C:\projects\my-app" -Resume -MaxRounds 5
```

---

### 2. บน macOS / Linux (ใช้ `agent-loop.sh`)

เปิด Terminal แล้วรันคำสั่งตามรูปแบบนี้:

```bash
./agent-loop.sh "โฟลเดอร์โปรเจกต์" "คำสั่งที่ต้องการให้ทำ" [จำนวนรอบสูงสุด]
```

หรือระบุด้วย Flags:
```bash
./agent-loop.sh -d "โฟลเดอร์โปรเจกต์" -t "คำสั่งที่ต้องการให้ทำ" -m [จำนวนรอบสูงสุด] [-r|--resume]
```

**ตัวอย่างการใช้งาน:**
```bash
# ตัวอย่าง: รันแบบใส่ค่าเรียงกัน
./agent-loop.sh /Users/username/projects/my-app "Fix login token expiration bug and add tests"

# ตัวอย่าง: รันแบบใช้ Flags กำหนดไม่เกิน 5 รอบ
./agent-loop.sh -d /Users/username/projects/my-app -t "Audit security for OWASP Top 10 and patch vulnerabilities" -m 5

# ตัวอย่าง: สั่งรันต่อจาก Task ล่าสุดที่ยังไม่จบ (เพิ่มอีก 5 รอบ หรือตาม default 8 รอบ)
./agent-loop.sh -d /Users/username/projects/my-app -r
./agent-loop.sh -d /Users/username/projects/my-app -r -m 5
```

---

## ผลลัพธ์และ Logs ที่ได้

ขณะทำงาน ระบบจะสร้างโฟลเดอร์เก็บประวัติไว้ในโปรเจกต์ปลายทางที่:
```text
your-project/
└── .agent-loop/
    └── task-YYYYMMDD-HHMMSS/
        ├── activity.log        # บันทึกสถานะการทำงานแต่ละขั้นตอน
        ├── current-diff.txt    # diff โค้ดที่มีการเปลี่ยนแปลง
        ├── review.md           # รายงานที่ Claude วิเคราะห์
        ├── qa-report.md        # ผลการตรวจของ Codex (PASS / FAIL)
        └── log/                # log เต็มของ AI แต่ละรอบ
```

---

## การทำงานเมื่อเสร็จสิ้น
- **เมื่อผ่าน (PASS):** ระบบจะรวมโค้ดทั้งหมดที่แก้ไข และทำ Git Commit ให้ **1 Commit** อัตโนมัติ (เช่น `feat: <Task> (passed in 2 rounds)`) พร้อมให้นำไป `git push` ได้ทันที
- **เมื่อไม่ผ่านจนครบ Max Rounds:** ระบบจะแจ้งเตือนว่าต้องให้คนเข้ามาดูเพิ่มเติม (Human Review) โดยไม่สร้าง Commit ทิ้งไว้
