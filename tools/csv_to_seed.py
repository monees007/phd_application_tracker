import pandas as pd, json, re, hashlib
from datetime import date

SRC = "tools/PG_-_Sheet5.csv"
# Every deadline in the sheet is day+month with NO year. Two rows leak "2026"
# (Funded col: "06/03/2026", "15.Apr.2026"), so we resolve all of them to this year.
DEADLINE_YEAR = 2026

MONTHS = {m: i for i, m in enumerate(
    ["jan","feb","mar","apr","may","jun","jul","aug","sep","oct","nov","dec"], 1)}

def parse_deadline(v):
    if not isinstance(v, str) or not v.strip():
        return None
    m = re.match(r"^\s*(\d{1,2})\s+([A-Za-z]{3,})\s*$", v.strip())
    if not m:
        return None
    day, mon = int(m.group(1)), m.group(2)[:3].lower()
    if mon not in MONTHS:
        return None
    return date(DEADLINE_YEAR, MONTHS[mon], day).isoformat()

def parse_fee(v):
    if not isinstance(v, str) or not v.strip():
        return None, None
    m = re.match(r"^\s*([\d.]+)\s*([A-Za-z]{3})\s*$", v.strip())
    if m:
        return float(m.group(1)), m.group(2).upper()
    return None, None

df = pd.read_csv(SRC, header=1).drop(columns=["Unnamed: 0"])
df = df.dropna(how="all")

out = []
unparsed_funded = []
for i, r in df.iterrows():
    college = str(r["College"]).strip() if pd.notna(r["College"]) else ""
    course  = str(r["Course"]).strip() if pd.notna(r["Course"]) else ""
    if not college and not course:
        continue

    raw_deadline = r["Deadline"] if pd.notna(r["Deadline"]) else None
    deadline = parse_deadline(raw_deadline)

    # "Funded" col: only one clean boolean ("Yes"); two cells hold stray dates.
    # Do NOT guess — keep the literal text in notes so nothing is invented.
    funded_raw = str(r["Funded"]).strip() if pd.notna(r["Funded"]) else ""
    funded = None
    if funded_raw.lower() in ("yes", "true"):
        funded = True
    elif funded_raw.lower() in ("no", "false"):
        funded = False
    elif funded_raw:
        unparsed_funded.append((college, course, funded_raw))

    fee, fee_ccy = parse_fee(r["App Fee"] if pd.notna(r["App Fee"]) else None)

    link_raw = str(r["Link to apply"]).strip() if pd.notna(r["Link to apply"]) else ""
    link = link_raw if link_raw.lower().startswith("http") else ""
    # one row has a job TITLE in the link column instead of a URL
    link_note = link_raw if (link_raw and not link) else ""

    applied = str(r["Applied Status"]).strip().lower() == "true"
    result  = str(r["Application status"]).strip().lower() if pd.notna(r["Application status"]) else ""

    if result == "rejected":
        status = "rejected"
    elif result == "accepted":
        status = "accepted"
    elif applied:
        status = "applied"
    else:
        status = "notApplied"

    notes = []
    if pd.notna(r["Info"]) and str(r["Info"]).strip():
        notes.append(str(r["Info"]).strip())
    if funded_raw and funded is None:
        notes.append(f'Sheet "Funded" column held: {funded_raw}')
    if link_note:
        notes.append(f'Sheet "Link to apply" column held (not a URL): {link_note}')
    if raw_deadline is not None and deadline is None:
        notes.append(f'Sheet "Deadline" column held: {raw_deadline}')

    tags = []
    if isinstance(r["Info"], str) and "marie" in r["Info"].lower():
        tags.append("Marie-Curie")

    pid = "seed_" + hashlib.sha1(f"{college}|{course}|{raw_deadline}".encode()).hexdigest()[:12]

    out.append({
        "id": pid,
        "university": college,
        "programme": course,
        "deadline": deadline,
        "deadlineYearAssumed": deadline is not None,
        "funded": funded,
        "applicationFee": fee,
        "feeCurrency": fee_ccy,
        "link": link,
        "status": status,
        "notes": "\n".join(notes),
        "tags": tags,
        "country": None,
    })

with open("assets/seed/positions.json", "w") as f:
    json.dump({"schemaVersion": 1, "deadlineYearAssumed": DEADLINE_YEAR,
               "source": "PG_-_Sheet5.csv", "positions": out}, f, indent=2)

from collections import Counter
print("rows written:", len(out))
print("status:", Counter(p["status"] for p in out))
print("no deadline:", sum(1 for p in out if not p["deadline"]))
print("with link:", sum(1 for p in out if p["link"]))
print("unparsed Funded cells:", unparsed_funded)
print("earliest/latest:", min(p['deadline'] for p in out if p['deadline']), max(p['deadline'] for p in out if p['deadline']))
