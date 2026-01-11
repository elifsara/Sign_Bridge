from fastapi import FastAPI, File, UploadFile
import numpy as np
import cv2
import mediapipe as mp
import math

app = FastAPI()

# --- AYARLAR ---
DEBUG_MODE = True  # Bilgisayarda pencere açılsın

# --- MEDIAPIPE AYARLARI ---
mp_hands = mp.solutions.hands
mp_drawing = mp.solutions.drawing_utils

# Görsel Stil (Kırmızı Eklemler, Yeşil Çizgiler)
landmark_style = mp_drawing.DrawingSpec(color=(0, 0, 255), thickness=3, circle_radius=3)
connection_style = mp_drawing.DrawingSpec(
    color=(0, 255, 0), thickness=2, circle_radius=2
)

hands = mp_hands.Hands(
    static_image_mode=True, max_num_hands=1, min_detection_confidence=0.5
)


def calculate_distance(p1, p2):
    return math.sqrt((p1.x - p2.x) ** 2 + (p1.y - p2.y) ** 2)


def get_finger_states(hand_landmarks, hand_label):
    tips = [4, 8, 12, 16, 20]  # Parmak Uçları
    bases = [2, 5, 9, 13, 17]  # Parmak Kökleri
    fingers = []

    # Sağ ve Sol el için başparmak zıt yönlere açılır.

    thumb_tip = hand_landmarks.landmark[tips[0]]
    thumb_base = hand_landmarks.landmark[bases[0]]

    # MediaPipe Mirroring (Aynalama) durumuna göre bazen ters algılayabilir.
    # Genelde:
    # Left Hand (Ekranda): Başparmak SAĞA açılır (Tip X > Base X)
    # Right Hand (Ekranda): Başparmak SOLA açılır (Tip X < Base X)

    if hand_label == "Left":
        # Sol el için kural
        if thumb_tip.x > thumb_base.x:
            fingers.append(1)  # Açık
        else:
            fingers.append(0)  # Kapalı
    else:
        # Sağ el için kural (Right)
        if thumb_tip.x < thumb_base.x:
            fingers.append(1)  # Açık
        else:
            fingers.append(0)  # Kapalı

    # --- 2. DİĞER 4 PARMAK (Mesafe Analizi - El fark etmez) ---
    wrist = hand_landmarks.landmark[0]
    for i in range(1, 5):
        tip_dist = calculate_distance(hand_landmarks.landmark[tips[i]], wrist)
        base_dist = calculate_distance(hand_landmarks.landmark[bases[i]], wrist)

        # Eğer parmak ucu bileğe, parmak kökünden daha uzaksa -> Açıktır
        fingers.append(1 if tip_dist > base_dist else 0)

    return fingers


@app.post("/predict")
async def predict(file: UploadFile = File(...)):
    contents = await file.read()
    nparr = np.frombuffer(contents, np.uint8)
    image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

    image_rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
    results = hands.process(image_rgb)

    response_text = ""

    if results.multi_hand_landmarks and results.multi_handedness:
        # Elin 'Sol' mu 'Sağ' mı olduğunu al (Döngü içinde index ile eşleştir)
        for idx, hand_landmarks in enumerate(results.multi_hand_landmarks):

            # Hangi el olduğunu tespit et (Left / Right)
            hand_label = results.multi_handedness[idx].classification[0].label

            # --- GÖRSELLEŞTİRME ---
            if DEBUG_MODE:
                mp_drawing.draw_landmarks(
                    image,
                    hand_landmarks,
                    mp_hands.HAND_CONNECTIONS,
                    landmark_style,
                    connection_style,
                )

            # --- ANALİZ (Eli de gönderiyoruz artık) ---
            fingers = get_finger_states(hand_landmarks, hand_label)

            # Sözlük (Dictionary) - Hareket Tanımları
            gestures = {
                (0, 0, 0, 0, 0): "A",  # Yumruk
                (1, 1, 1, 1, 1): "B",  # Açık El
                (0, 1, 1, 0, 0): "V",  # Zafer
                (1, 1, 0, 0, 0): "C",  # C harfi (veya L)
                (0, 1, 0, 0, 0): "D",  # 1 Sayısı
                (0, 0, 0, 0, 1): "I",  # Serçe parmak
                (1, 0, 0, 0, 1): "Y",  # Telefon
            }

            finger_tuple = tuple(fingers)
            prediction = gestures.get(finger_tuple, "Tanimlanamadi")

            # Birden fazla el varsa sonuncuyu almasın diye birleştir
            response_text = prediction

            print(f"El: {hand_label} | Parmak: {fingers} -> Tahmin: {response_text}")

            # Ekrana Yaz
            cv2.rectangle(image, (0, 0), (640, 60), (0, 0, 0), -1)
            cv2.putText(
                image,
                f"Tahmin: {response_text}",
                (20, 45),
                cv2.FONT_HERSHEY_SIMPLEX,
                1.5,
                (0, 255, 0),
                2,
                cv2.LINE_AA,
            )

    if DEBUG_MODE:
        cv2.imshow("SignBridge AI Server View", image)
        cv2.waitKey(1)

    return {"prediction": response_text}


# Çalıştırma:
# python -m uvicorn demo:app --host 0.0.0.0 --port 8000
