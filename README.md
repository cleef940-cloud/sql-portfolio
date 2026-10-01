#Credit Risk Analysis

A short analysis of loan default risk using a public risk dataset, covering data cleaning , SQL exploration, a logistic regression model and outlier detection.

## Dataset 
Source: Kaggle "Credit Risk Dataset" (32,581 rows, 12 columns).

## 1. Data cleaning
-Removed 170 duplicate rows.
-Removed rows with impossible ages (under 18 over 100).
-Fixed employment lengths that implied working before age 16, set to missing then filled with the median.
-Filled missing 'person_emp_length' and 'loan_int_rate' with the median.
-Final dataset: 32,411 rows, documented in 'cleaning_log.csv'.

##2. QL ANAlysis (PostgreSQL)
-BY grade :  default rate rises steadily from grade A (10.0%) to frade(98.4%), confirm9ng the grading system separates risk correctly. Grades E-G have small samples sizes, so their rates are less certain.
-By home ownership: renters default ar 31.6% , over 4x the rate of outright homeowners (7.5%). Mortgage holders sit in between (12.6%).
-By loan purpose: debt consolidation (28.7%) and medical loans (26.8%) default the most. Venture (14.9%) and education (17.3%) loans default least.
-By credit history length: fairly flat(21-24%), a weak signal on its own compared to grade or ownership.
-Top risk groups : combining grade and ownership sharpens the picture, Grade G + mortgage defaults 100% of the time (31 loans, small sample).
Grade F + rent defaults 78% (127 loans). Renting shows up in 6 of the top 10 riskiest combinations.

##3. Logistic Regression Model
- Accuracy: 86.3%
- Recall: 54.1% (catches just over half of actual defaulters)
- Of 1,403 true defaulters in the test set, 644 were missed. This matters
  more than accuracy, since missing a defaulter is costlier than flagging
  a safe borrower by mistake.

**Key drivers (strongest push toward default):**
1. `loan_percent_income` (loan size relative to income) — by far the
   strongest factor.
2. Loan grades D and E.
3. Renting (`person_home_ownership_RENT`).

**Key drivers (strongest push toward safety):**
- Larger loan amounts, owning a home outright, venture-purpose loans.

Note: `loan_amnt`'s negative coefficient doesn't mean bigger loans are
simply safer on their own, a direct SQL check showed the raw default rate
by loan size is not a straight line (20.8% → 18.0% → 25.7%). The
coefficient reflects its effect *after* accounting for `loan_percent_income`
and other factors, not a standalone rule.

## 4. Outlier Detection (Mahalanobis Distance)
Flagged 1,871 records (5.8%) as statistically unusual across 7 numeric
columns, using a chi-square cutoff. The most extreme cases are driven by
very high income (up to ~2 million vs. a typical 49k-80k), but their loan
amounts and loan-to-income ratios remain normal and internally consistent.
These look like genuine high-income borrowers rather than data entry
errors, and are flagged for review rather than removed.

## Files
- `credit_clean.csv` — cleaned dataset
- `cleaning_log.csv` — record of what was fixed
- `credit_with_outliers.csv` — cleaned data plus outlier flags
- `model.py` — full pipeline: cleaning checks, SQL-ready export, model
  training, evaluation, and outlier detection
- `default_rate_by_grade.csv`, `default_rate_by_ownership.csv`,
  `default_rate_by_intent.csv`, `default_rate_by_credit_history.csv` —
  SQL query results

## Tools
PostgreSQL, Python (pandas, scikit-learn, scipy)