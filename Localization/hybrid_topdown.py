import cv2
import numpy as np

def find_best_anchor(query_img, anchor_frames):
    """
    Compares query image against all video anchors and returns the best match.
    """
    sift = cv2.SIFT_create()
    kp_q, des_q = sift.detectAndCompute(query_img, None)
    
    best_match_count = 0
    best_anchor = None
    
    for anchor in anchor_frames:
        kp_a, des_a = sift.detectAndCompute(anchor, None)
        
        # Match features
        bf = cv2.BFMatcher()
        matches = bf.knnMatch(des_q, des_a, k=2)
        
        # Ratio test to find 'good' matches
        good = [m for m, n in matches if m.distance < 0.75 * n.distance]
        
        if len(good) > best_match_count:
            best_match_count = len(good)
            best_anchor = anchor
            
    return best_anchor, best_match_count

def get_bev_coordinates(ref_img, query_img):
    """
    Estimates 2D Bird's Eye View position relative to the reference.
    """
    # 1. Detect features
    sift = cv2.SIFT_create()
    kp1, des1 = sift.detectAndCompute(ref_img, None)
    kp2, des2 = sift.detectAndCompute(query_img, None)

    # 2. Match
    bf = cv2.BFMatcher()
    matches = bf.knnMatch(des1, des2, k=2)
    good = [m for m, n in matches if m.distance < 0.7 * n.distance]

    if len(good) > 10:
        src_pts = np.float32([kp1[m.queryIdx].pt for m in good]).reshape(-1, 1, 2)
        dst_pts = np.float32([kp2[m.trainIdx].pt for m in good]).reshape(-1, 1, 2)

        # 3. Find Homography (The 2D relationship)
        M, mask = cv2.findHomography(src_pts, dst_pts, cv2.RANSAC, 5.0)
        
        # 4. Extract Translation from the Matrix
        # This is a simplification to get a BEV estimate
        tx = M[0, 2] # Lateral movement
        ty = M[1, 2] # Forward/Backward movement
        
        return tx, ty
    return None, None

# Usage
query_img = cv2.imread('images/frame_0103.jpg', 0)

# Load your anchor frames into a list
anchor_paths = ['images/frame_0018.jpg', 'images/frame_0081.jpg', 'images/frame_0047.jpg', 'images/frame_0105.jpg']
anchor_frames = [cv2.imread(p, 0) for p in anchor_paths]

# Now you can run the function
best_pos, score = find_best_anchor(query_img, anchor_frames)

print(best_pos)

# x, y = get_bev_coordinates(best_anchor, query_img)