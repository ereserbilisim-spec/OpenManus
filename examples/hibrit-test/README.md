# Hibrit Sistem Demo — CAMEL-AI + OpenManus

Tarih: 2026-10-01
Süre: ~5 dakika (2 framework birlikte)

## Amaç

İki farklı MCP server'ın (OpenManus + CAMEL-AI) birlikte gerçek bir iş çıkarabildiğini kanıtlamak.

## Senaryo

Görev: Basit bir Todo SaaS MVP'si için plan + kod + test

## Akış

### ADIM 1: CAMEL-AI (Planlama)

camel__role_play ile PM ve Dev diyalogu:

PM: MVP Kapsamı — kullanıcı kaydı/girişi, görev ekleme/silme/tamamlama, listeleme, basit filtreleme. Stack: React Native (Expo) + Firebase.

Dev: Offline-first için Firestore yeterli mi? Expo managed workflow → EAS Build geçişi? Analitik için custom event?

Model: nvidia/nemotron-3-ultra-550b-a55b:free

### ADIM 2: OpenManus (Kod + Test)

sandbox_python_execute ve bash ile:

1. ~/Desktop/hibrit-test/ dizini oluşturuldu
2. todo_api.py yazıldı (Flask + in-memory, 4 endpoint)
3. Agent kendi venv'ini kurdu (proaktif)
4. Sandbox'ta test edildi

### ADIM 3: Host Doğrulama

GET: 200 OK
POST: 201 OK
PUT: 200 OK
DELETE: 204 OK

## Üretilen Kod

todo_api.py — Flask API (1253 byte)

- GET /todos — tüm görevleri listele
- POST /todos — yeni görev
- PUT /todos/<id> — güncelle
- DELETE /todos/<id> — sil

## Sonuç

Kanıtlananlar:
- CAMEL rol simülasyonu
- CAMEL teknik kararlar
- OpenManus kod yazma (fabricasyon yok)
- OpenManus proaktif venv kurulumu
- Sandbox test
- Host doğrulama (200/201/200/204)

Sistem otonom, hibrit, kendi kendine yeterli.

## Yeniden Üretmek İçin

OpenClaw TUI'da:

camel__role_play kullanarak:
- task: "Todo app MVP planla"
- assistant_role: "PM"
- user_role: "Dev"
- turns: 1

Sonra:
sandbox_python_execute ile Flask API yaz ve test et
