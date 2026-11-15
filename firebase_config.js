// HealthTracker Firebase Configuration
// Firebase 콘솔(프로젝트 설정: health-tracker-70637) 발급 설정값
window.FIREBASE_CONFIG = {
  apiKey: "AIzaSyA9LwZWbiXVcE5T5-Vm6QX6pB7xa4MZVxo",
  authDomain: "health-tracker-70637.firebaseapp.com",
  projectId: "health-tracker-70637",
  storageBucket: "health-tracker-70637.firebasestorage.app",
  messagingSenderId: "740112741763",
  appId: "1:740112741763:web:1b0ac9b2f642ff9edd72b6"
};

// 로컬 스토리지에 사용자가 직접 덮어쓴 설정이 있다면 우선 적용
try {
  const localSavedConfig = localStorage.getItem('health_tracker_firebase_config');
  if (localSavedConfig) {
    const parsed = JSON.parse(localSavedConfig);
    if (parsed && parsed.projectId) {
      window.FIREBASE_CONFIG = parsed;
    }
  }
} catch (e) {
  console.warn('Firebase config load error:', e);
}
