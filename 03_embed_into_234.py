import numpy as np

# -------------------------------------------------
# Load master windows
# -------------------------------------------------

spikes = np.load(r"bch001_test\master_spike_windows.npy")
controls = np.load(r"bch001_test\master_control_windows.npy")

print("Spike windows :", spikes.shape)
print("Control windows:", controls.shape)

# -------------------------------------------------
# Load selected channels
# -------------------------------------------------

selected = np.load(r"bch001_test\selected_160_indices.npy")

print("Selected channels:", len(selected))

# -------------------------------------------------
# Keep only the selected 160 channels
# -------------------------------------------------

spikes160 = spikes[:, selected, :]
controls160 = controls[:, selected, :]

print("Spike160 :", spikes160.shape)
print("Control160:", controls160.shape)

# -------------------------------------------------
# Embed into 234 rows
# -------------------------------------------------

N_SPIKE = spikes160.shape[0]
N_CONTROL = controls160.shape[0]

spikes234 = np.zeros((N_SPIKE, 234, 1024), dtype=np.float32)
controls234 = np.zeros((N_CONTROL, 234, 1024), dtype=np.float32)

# Put the real channels in rows 0-159
spikes234[:, :160, :] = spikes160
controls234[:, :160, :] = controls160

print("Spike234 :", spikes234.shape)
print("Control234:", controls234.shape)

# -------------------------------------------------
# Labels
# -------------------------------------------------

spike_labels = np.ones(N_SPIKE, dtype=np.int64)
control_labels = np.zeros(N_CONTROL, dtype=np.int64)

# -------------------------------------------------
# Save
# -------------------------------------------------

np.save(r"bch001_test\famed_spikes_234.npy", spikes234)
np.save(r"bch001_test\famed_controls_234.npy", controls234)

np.save(r"bch001_test\famed_spike_labels.npy", spike_labels)
np.save(r"bch001_test\famed_control_labels.npy", control_labels)

print("\nSaved FAMED-ready tensors.")