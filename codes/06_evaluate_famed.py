import numpy as np

from sklearn.metrics import (
    roc_auc_score,
    roc_curve,
    confusion_matrix,
    accuracy_score,
    precision_score,
    recall_score,
    f1_score
)

# --------------------------------------------------
# Load results
# --------------------------------------------------

y = np.load(r"bch001_test\evaluation_labels.npy")
prob = np.load(r"bch001_test\famed_probabilities.npy")

print("Samples:", len(y))
print("Positive:", y.sum())
print("Negative:", len(y)-y.sum())

# --------------------------------------------------
# ROC AUC
# --------------------------------------------------

auc = roc_auc_score(y, prob)

print("\n==========================")
print("ROC AUC")
print("==========================")
print(f"AUC = {auc:.4f}")

# --------------------------------------------------
# Evaluate multiple thresholds
# --------------------------------------------------

thresholds = [0.10, 0.30, 0.50, 0.70, 0.90]

for th in thresholds:

    pred = (prob >= th).astype(int)

    cm = confusion_matrix(y, pred)

    tn, fp, fn, tp = cm.ravel()

    acc = accuracy_score(y, pred)
    prec = precision_score(y, pred, zero_division=0)
    rec = recall_score(y, pred)
    f1 = f1_score(y, pred)

    spec = tn / (tn + fp)

    print("\n===================================")
    print(f"Threshold = {th:.2f}")
    print("===================================")

    print(cm)

    print(f"Accuracy    : {acc:.4f}")
    print(f"Precision   : {prec:.4f}")
    print(f"Recall      : {rec:.4f}")
    print(f"Specificity : {spec:.4f}")
    print(f"F1-score    : {f1:.4f}")

# --------------------------------------------------
# Save ROC curve
# --------------------------------------------------

fpr, tpr, thr = roc_curve(y, prob)

np.save(r"bch001_test\roc_fpr.npy", fpr)
np.save(r"bch001_test\roc_tpr.npy", tpr)
np.save(r"bch001_test\roc_thresholds.npy", thr)

print("\nROC arrays saved.")