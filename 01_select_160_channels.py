import numpy as np

# --------------------------------------------
# Load master metadata
# --------------------------------------------

channel_names = np.load(
    r"bch001_test\master_channel_names.npy",
    allow_pickle=True,
)

channel_positions = np.load(
    r"bch001_test\master_channel_positions.npy"
)

print("Channels:", len(channel_names))
print("Positions:", channel_positions.shape)

# --------------------------------------------
# Basic statistics
# --------------------------------------------

print("\nFirst 10 channels:\n")

for i in range(10):
    print(
        f"{i:3d}",
        channel_names[i],
        channel_positions[i]
    )

# --------------------------------------------
# Save index list
# --------------------------------------------

all_idx = np.arange(len(channel_names))

np.save(
    r"bch001_test\all_305_indices.npy",
    all_idx
)

print("\nSaved index file.")