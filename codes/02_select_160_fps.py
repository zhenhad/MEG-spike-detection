import numpy as np

# ----------------------------------------
# Load sensor centers
# ----------------------------------------

xyz = np.load(
    r"bch001_test\master_channel_centers.npy"
)

print("Sensor centers:", xyz.shape)

# ----------------------------------------
# Farthest Point Sampling
# ----------------------------------------

selected = [0]

while len(selected) < 160:

    chosen = xyz[selected]

    # distance from every sensor to nearest selected sensor
    d = np.linalg.norm(
        xyz[:, None, :] - chosen[None, :, :],
        axis=2
    )

    nearest = d.min(axis=1)

    nearest[selected] = -1

    next_idx = np.argmax(nearest)

    selected.append(int(next_idx))

selected = np.array(selected)

print("Selected:", len(selected))

# ----------------------------------------
# Save
# ----------------------------------------

np.save(
    r"bch001_test\selected_160_indices.npy",
    selected
)

print("Saved selected_160_indices.npy")

# ----------------------------------------
# Show first few channels
# ----------------------------------------

names = np.load(
    r"bch001_test\master_channel_names.npy",
    allow_pickle=True
)

print("\nFirst 20 selected channels:")

for i in selected[:20]:
    print(i, names[i])