import numpy as np
import torch
from scipy import stats

from Model.FAMED_model import get_FAMED_Cls

# --------------------------------------------------
# Load evaluation dataset
# --------------------------------------------------

X = np.load(r"bch001_test\evaluation_windows.npy")
y = np.load(r"bch001_test\evaluation_labels.npy")

print("Evaluation windows:", X.shape)
print("Labels:", y.shape)

# --------------------------------------------------
# Load pretrained classifier
# --------------------------------------------------

model = get_FAMED_Cls(1024)

ckpt = torch.load(
    "../data/model_weights/FAMED/FAMED_Classification_Weight_Fold9.ckpt",
    map_location=torch.device("cpu"),
)

model.load_state_dict(ckpt)
model.eval()

print("Classification model loaded.")

# --------------------------------------------------
# Run inference
# --------------------------------------------------

probabilities = []

with torch.no_grad():

    for i, window in enumerate(X):

        # ---- identical preprocessing to the notebook ----
        data = stats.zscore(window, axis=None)

        data_tensor = torch.from_numpy(
            data[np.newaxis, np.newaxis].astype(np.float32)
        )

        out = model(data_tensor).sigmoid().item()

        probabilities.append(out)

        if (i + 1) % 25 == 0:
            print(f"{i+1}/{len(X)}")

probabilities = np.array(probabilities)

# --------------------------------------------------
# Save
# --------------------------------------------------

np.save(
    r"bch001_test\famed_probabilities.npy",
    probabilities
)

print("\nSaved probabilities.")

# --------------------------------------------------
# Quick summary
# --------------------------------------------------

spike_prob = probabilities[y == 1]
control_prob = probabilities[y == 0]

print("\n===========================")
print("Spike windows")
print("===========================")
print("Count:", len(spike_prob))
print("Mean :", spike_prob.mean())
print("Median:", np.median(spike_prob))
print("Max:", spike_prob.max())
print("Min:", spike_prob.min())

print("\n===========================")
print("Control windows")
print("===========================")
print("Count:", len(control_prob))
print("Mean :", control_prob.mean())
print("Median:", np.median(control_prob))
print("Max:", control_prob.max())
print("Min:", control_prob.min())