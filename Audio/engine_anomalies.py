import librosa
import numpy as np
from sklearn.metrics.pairwise import cosine_similarity

# def get_audio_fingerprint(audio_path):
#     y, sr = librosa.load(audio_path, sr=16000)
#     # 1. Normalize volume to -20dB
#     y = librosa.util.normalize(y) 
#     # 2. Extract MFCCs (The 'Fingerprint')
#     mfccs = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13)
#     return mfccs

# # Pre-calculate MFCC for normal engine sound. Gives us understanding of the "texture" of normal audio
# golden_mfcc = get_audio_fingerprint('catengine10.mp3')

# def check_anomaly(live_buffer):
#     live_mfcc = librosa.feature.mfcc(y=live_buffer, sr=16000, n_mfcc=13)
#     # Use Cosine Similarity or DTW distance
#     dist, wp = librosa.sequence.dtw(X=golden_mfcc, Y=live_mfcc, metric='cosine')
#     # A 'distance' near 0 is healthy. A spike means an anomaly.
#     return np.mean(dist)
# input_mfcc = get_audio_fingerprint("catenginetest.mp3")[:,:golden_mfcc.shape[1]]
# score = cosine_similarity(golden_mfcc, input_mfcc)[0][0]
# print(f"Similarity Score: {score:.4f}")
# import librosa
# import numpy as np
# from sklearn.metrics.pairwise import cosine_similarity

def get_fingerprint(audio_path):
    y, sr = librosa.load(audio_path, sr=16000)
    y = librosa.util.normalize(y) 
    mfccs = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=13)
    
    # NEW: Average across time (axis=1) to get a 1D vector of length 13
    # Then reshape to (1, 13) so cosine_similarity is happy
    return np.mean(mfccs, axis=1).reshape(1, -1)

# Pre-calculate
golden_vec = get_fingerprint('catengine10.mp3')
test_vec = get_fingerprint('catenginetest.mp3')

# This will ALWAYS work regardless of audio length
score = cosine_similarity(golden_vec, test_vec)[0][0]
print(f"Similarity Score: {score:.4f}")