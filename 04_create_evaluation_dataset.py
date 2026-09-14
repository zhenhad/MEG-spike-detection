import numpy as np

# ---------------------------------------------------
# Load FAMED-ready tensors
# ---------------------------------------------------

spikes = np.load(r"bch001_test\famed_spikes_234.npy")
controls = np.load(r"bch001_test\famed_controls_234.npy")

print("Spikes :", spikes.shape)
print("Controls:", controls.shape)

# ---------------------------------------------------
# Merge
# ---------------------------------------------------

X = np.concatenate([spikes, controls], axis=0)

y = np.concatenate([
    np.ones(len(spikes), dtype=np.int64),
    np.zeros(len(controls), dtype=np.int64)
])

print("\nEvaluation dataset")

print("X:", X.shape)
print("y:", y.shape)

print("Positive:", y.sum())
print("Negative:", len(y)-y.sum())

# ---------------------------------------------------
# Save
# ---------------------------------------------------

np.save(
    r"bch001_test\evaluation_windows.npy",
    X
)

np.save(
    r"bch001_test\evaluation_labels.npy",
    y
)

print("\nSaved evaluation dataset.")