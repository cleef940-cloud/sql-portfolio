import pandas as pd

raw = pd.read_csv("credit_risk_dataset.csv")
df = raw.copy()
log = []

def note(issue, column, rows, action):
    log.append({"issue": issue, "column": column,
                "rows_affected": int(rows), "action": action})

print("Rows before:", len(raw))

# 1. Duplicates
n = df.duplicated().sum()
df = df.drop_duplicates()
note("Duplicate rows", "all", n, "Dropped, kept first")

# 2. Impossible values
bad_age = (df.person_age < 18) | (df.person_age > 100)
note("Impossible age (<18 or >100)", "person_age", bad_age.sum(), "Dropped rows")
df = df[~bad_age]

bad_emp = df.person_emp_length > (df.person_age - 16)
note("Employment length longer than plausible working life",
     "person_emp_length", bad_emp.sum(), "Set to blank, then filled with median")
df.loc[bad_emp, "person_emp_length"] = None

# 3. Missing values
for col in ["person_emp_length", "loan_int_rate"]:
    n = df[col].isna().sum()
    df[col] = df[col].fillna(df[col].median())
    note("Missing values", col, n, "Filled with median")

print("Rows after:", len(df))
pd.DataFrame(log).to_csv("cleaning_log.csv", index=False)
df.to_csv("credit_clean.csv", index=False)
print("Done. Files saved: credit_clean.csv and cleaning_log.csv")