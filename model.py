import pandas as pd

df = pd.read_csv("credit_clean.csv")
print(df.shape)
print(df.columns.tolist())

df_model = pd.get_dummies(df, columns=[
    "person_home_ownership",
    "loan_intent",
    "loan_grade",
    "cb_person_default_on_file"
], drop_first=True)

print(df_model.shape)
print(df_model.columns.tolist())

X = df_model.drop(columns=["loan_status"])
y = df_model["loan_status"]

print(X.shape)
print(y.shape)

from sklearn.model_selection import train_test_split

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42
)

print(X_train.shape)
print(X_test.shape)

from sklearn.preprocessing import StandardScaler

scaler = StandardScaler()
X_train_scaled = scaler.fit_transform(X_train)
X_test_scaled = scaler.transform(X_test)

from sklearn.linear_model import LogisticRegression

model = LogisticRegression(max_iter=1000)
model.fit(X_train_scaled, y_train)

print("Training complete")

from sklearn.metrics import accuracy_score, recall_score, confusion_matrix

y_pred = model.predict(X_test_scaled)

acc = accuracy_score(y_test, y_pred)
rec = recall_score(y_test, y_pred)

print("Accuracy:", round(acc, 3))
print("Recall:", round(rec, 3))
print("Confusion matrix:")
print(confusion_matrix(y_test, y_pred))

coefficients = pd.DataFrame({
    "feature": X.columns,
    "coefficient": model.coef_[0]
})

coefficients = coefficients.sort_values("coefficient", ascending=False)
print(coefficients)

import numpy as np
from scipy.stats import chi2

numeric_cols = ["person_age", "person_income", "person_emp_length","loan_amnt","loan_int_rate","loan_percent_income","cb_person_cred_hist_length"]
numeric_data = df[numeric_cols]
print(numeric_data.shape)

mean_vec = numeric_data.mean().values
cov_matrix = numeric_data.cov().values
inv_cov_matrix = np.linalg.inv(cov_matrix)

diff = numeric_data.values - mean_vec
left = np.dot(diff, inv_cov_matrix)
mahal_sq = np.sum(left * diff, axis=1)

df ["mahalanobis_dist"] = np.sqrt(mahal_sq)

print(df["mahalanobis_dist"].describe())

threshold = np.sqrt(chi2.ppf(0.975, df=len(numeric_cols)))
print("Threshold:", round(threshold, 2))

df["is_outlier"] = df["mahalanobis_dist"] > threshold

print(df["is_outlier"].sum(), "outliers flagged out of", len(df))

top_outliers = df.sort_values("mahalanobis_dist", ascending=False).head(10)
print(top_outliers[numeric_cols + ["mahalanobis_dist"]])

df.to_csv("credit_with_outliners.csv", index=False)
print("Saved credit_with_outliers.csv")

pd.set_option('display.max_columns', None)
print(top_outliers[numeric_cols + ["mahalanobis_dist"]])
