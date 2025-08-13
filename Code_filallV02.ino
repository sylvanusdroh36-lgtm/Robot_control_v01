#include <WiFi.h>
#include <WebServer.h>
#include <WebSocketsServer.h>
#include <ArduinoJson.h>
#include <WiFiUdp.h>
#include <ArduinoOTA.h>

// Configuration WiFi
const char* ssid = "FAB_MANAGER_WIFI";
const char* password = "24@Y'ELLO.LAB";

// Broches moteurs (L298N)
const int ENA = 32;
const int IN1 = 33;
const int IN2 = 25;
const int ENB = 14;
const int IN3 = 26;
const int IN4 = 27;

// LEDs et Buzzer
const int LED_GAUCHE = 12;
const int LED_DROITE = 13;
const int BUZZER_PIN = 15;

// Variables
int vitesse = 180; // Valeur par défaut (70% de 255)
WebServer server(80);
WebSocketsServer webSocket = WebSocketsServer(81);
bool ledsOn = false;
bool motorsStopped = true;
bool otaUpdating = false; // Drapeau pour suivre l'état OTA

void setup() {
  Serial.begin(115200);
  
  // Configuration des broches
  pinMode(ENA, OUTPUT);
  pinMode(IN1, OUTPUT);
  pinMode(IN2, OUTPUT);
  pinMode(ENB, OUTPUT);
  pinMode(IN3, OUTPUT);
  pinMode(IN4, OUTPUT);
  pinMode(LED_GAUCHE, OUTPUT);
  pinMode(LED_DROITE, OUTPUT);
  pinMode(BUZZER_PIN, OUTPUT);
  
  stopMotors();
  sequenceDemarrage();

  // WiFi en mode STA
  Serial.println("Connexion au réseau Wi-Fi...");
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);

  // Gestion améliorée de la connexion WiFi
  Serial.print("Connexion");
  unsigned long startTime = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - startTime < 15000) {
    delay(500);
    Serial.print(".");
  }
  Serial.println();

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("Échec de connexion WiFi! Mode AP activé.");
    WiFi.mode(WIFI_AP);
    WiFi.softAP("RobotAP", "password123");
    Serial.print("AP IP: ");
    Serial.println(WiFi.softAPIP());
  } else {
    Serial.println("Wi-Fi connecté !");
    Serial.print("IP locale: ");
    Serial.println(WiFi.localIP());
  }

  // ======== CONFIGURATION OTA ========
  Serial.println("Configuration OTA...");
  
  // Configuration de base
  ArduinoOTA.setHostname("RobotController"); // Nom du périphérique
  
  // Gestionnaires d'événements OTA
  ArduinoOTA.onStart([]() {
    otaUpdating = true;
    String type = (ArduinoOTA.getCommand() == U_FLASH) ? "sketch" : "filesystem";
    Serial.println("Début mise à jour OTA: " + type);
    stopMotors(); // Arrêter les moteurs pendant la mise à jour
    digitalWrite(LED_GAUCHE, HIGH);
    digitalWrite(LED_DROITE, HIGH);
  });
  
  ArduinoOTA.onEnd([]() {
    Serial.println("\nMise à jour terminée!");
    digitalWrite(LED_GAUCHE, LOW);
    digitalWrite(LED_DROITE, LOW);
    // Redémarrage nécessaire après mise à jour
    ESP.restart();
  });
  
  ArduinoOTA.onProgress([](unsigned int progress, unsigned int total) {
    int pourcentage = (progress * 100) / total;
    Serial.printf("Progression: %u%%\r", pourcentage);
    
    // Feedback visuel avec les LEDs
    static int lastPercentage = -1;
    if (pourcentage % 10 == 0 && pourcentage != lastPercentage) {
      digitalWrite(LED_GAUCHE, !digitalRead(LED_GAUCHE));
      digitalWrite(LED_DROITE, !digitalRead(LED_DROITE));
      lastPercentage = pourcentage;
    }
  });
  
  ArduinoOTA.onError([](ota_error_t error) {
    otaUpdating = false;
    Serial.printf("Erreur[%u]: ", error);
    if (error == OTA_AUTH_ERROR) Serial.println("Authentification échouée");
    else if (error == OTA_BEGIN_ERROR) Serial.println("Échec démarrage");
    else if (error == OTA_CONNECT_ERROR) Serial.println("Échec connexion");
    else if (error == OTA_RECEIVE_ERROR) Serial.println("Échec réception");
    else if (error == OTA_END_ERROR) Serial.println("Échec finalisation");
    
    // Signal d'erreur avec le buzzer
    for (int i = 0; i < 3; i++) {
      tone(BUZZER_PIN, 2000, 200);
      delay(300);
    }
    noTone(BUZZER_PIN);
  });
  
  ArduinoOTA.begin();
  Serial.println("OTA prêt");

  // Serveur HTTP
  server.on("/", HTTP_GET, handleRoot);
  server.on("/command", HTTP_GET, handleCommand);
  server.on("/ping", HTTP_GET, handlePing);
  server.on("/ota", HTTP_GET, []() {
    server.send(200, "text/plain", "Prêt pour mise à jour OTA. Utilisez l'IDE Arduino ou espota.py");
  });
  server.onNotFound(handleNotFound);
  server.begin();

  // WebSocket
  webSocket.begin();
  webSocket.onEvent(webSocketEvent);
  webSocket.enableHeartbeat(15000, 3000, 2);
  
  Serial.println("WebSocket démarré sur ws://" + WiFi.localIP().toString() + ":81");
  Serial.println("Serveur prêt");
}

void loop() {
  // Gestion OTA
  ArduinoOTA.handle();
  
  // Ne pas traiter les requêtes réseau pendant la mise à jour
  if (!otaUpdating) {
    server.handleClient();
    webSocket.loop();
  }
}

// ======== Handlers HTTP ========
void handleRoot() {
  server.send(200, "text/plain", "Robot Control - Envoyez des commandes via /command?cmd=XX\nOTA: /ota");
}

void handlePing() {
  server.send(200, "text/plain", "OK");
}

void handleNotFound() {
  server.send(404, "text/plain", "Endpoint non trouvé");
}

void handleCommand() {
  if (!server.hasArg("cmd")) {
    server.send(400, "text/plain", "Paramètre 'cmd' manquant");
    return;
  }

  String cmd = server.arg("cmd");
  traiterCommande(cmd);
  server.send(200, "application/json", "{\"status\":\"OK\",\"command\":\"" + cmd + "\"}");
}

// ======== Gestion WebSocket améliorée ========
void webSocketEvent(uint8_t num, WStype_t type, uint8_t* payload, size_t length) {
  // Bloquer les commandes pendant la mise à jour OTA
  if (otaUpdating) {
    webSocket.sendTXT(num, "{\"error\":\"Système occupé (mise à jour OTA en cours)\"}");
    return;
  }
  
  switch(type) {
    case WStype_TEXT: {
      // Ajout d'un log pour voir les données reçues
      Serial.printf("[WebSocket] Message reçu: %.*s\n", length, payload);
      
      DynamicJsonDocument doc(256);
      DeserializationError err = deserializeJson(doc, payload, length);
      
      if (err) {
        Serial.printf("Erreur JSON: %s\n", err.c_str());
        webSocket.sendTXT(num, "{\"error\":\"Format JSON invalide\"}");
        return;
      }

      // Traitement spécial pour le handshake
      if (doc.containsKey("cmd") && doc["cmd"] == "handshake") {
        webSocket.sendTXT(num, "{\"status\":\"connected\",\"version\":\"1.0\",\"type\":\"robot\"}");
        return;
      }

      String cmd = doc["cmd"] | "";
      if (cmd == "") {
        webSocket.sendTXT(num, "{\"error\":\"Commande manquante\"}");
        return;
      }

      // Gestion de la vitesse
      if (doc.containsKey("data") && doc["data"].containsKey("speed")) {
        int newSpeed = doc["data"]["speed"].as<int>();
        if (newSpeed >= 0 && newSpeed <= 255) {
          vitesse = newSpeed;
          Serial.printf("Vitesse mise à jour: %d\n", vitesse);
          // Mise à jour immédiate si les moteurs sont actifs
          if (!motorsStopped) {
            analogWrite(ENA, vitesse);
            analogWrite(ENB, vitesse);
          }
        } else {
          webSocket.sendTXT(num, "{\"error\":\"Vitesse invalide (0-255)\"}");
        }
      }
      
      traiterCommande(cmd);
      webSocket.sendTXT(num, "{\"status\":\"executed\",\"command\":\"" + cmd + "\"}");
      break;
    }
    
    case WStype_CONNECTED: {
      IPAddress ip = webSocket.remoteIP(num);
      Serial.printf("[WebSocket %u] Connecté depuis %s\n", num, ip.toString().c_str());
      webSocket.sendTXT(num, "{\"status\":\"connected\",\"version\":\"1.0\"}");
      break;
    }
      
    case WStype_DISCONNECTED:
      Serial.printf("[WebSocket %u] Déconnecté\n", num);
      break;
      
    case WStype_ERROR:
      Serial.printf("[WebSocket %u] Erreur\n", num);
      break;
      
    case WStype_PING:
      Serial.printf("[WebSocket %u] Ping reçu\n", num);
      break;
      
    case WStype_PONG:
      Serial.printf("[WebSocket %u] Pong reçu\n", num);
      break;
      
    default:
      break;
  }
}

// ======== Traitement des commandes ========
void traiterCommande(String cmd) {
  cmd.trim();
  if (cmd.isEmpty()) return;

  struct CommandHandler {
    const char* name;
    void (*action)();
  };

  static const CommandHandler handlers[] = {
    {"forward", avancer},
    {"backward", reculer},
    {"left", tournerGauche},
    {"right", tournerDroite},
    {"stop", stopMotors},
    {"led_toggle", toggleLEDs},
    {"buzzer", buzzerAlert},
    {"camera", handleCamera}
  };

  for (const auto& handler : handlers) {
    if (cmd == handler.name) {
      Serial.printf("Exécution: %s\n", handler.name);
      handler.action();
      return;
    }
  }
  
  Serial.printf("Commande inconnue: %s\n", cmd.c_str());
}

// ======== Fonctions moteurs ========
void avancer() {
  digitalWrite(IN1, HIGH);
  digitalWrite(IN2, LOW);
  digitalWrite(IN3, HIGH);
  digitalWrite(IN4, LOW);
  analogWrite(ENA, vitesse);
  analogWrite(ENB, vitesse);
  motorsStopped = false;
  ledsAvancer();
}

void reculer() {
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, HIGH);
  digitalWrite(IN3, LOW);
  digitalWrite(IN4, HIGH);
  analogWrite(ENA, vitesse);
  analogWrite(ENB, vitesse);
  motorsStopped = false;
  ledsReculer();
}

void tournerGauche() {
  digitalWrite(IN1, HIGH);
  digitalWrite(IN2, LOW);
  digitalWrite(IN3, LOW);
  digitalWrite(IN4, HIGH);
  analogWrite(ENA, vitesse);
  analogWrite(ENB, vitesse);
  motorsStopped = false;
  ledsGauche();
}

void tournerDroite() {
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, HIGH);
  digitalWrite(IN3, HIGH);
  digitalWrite(IN4, LOW);
  analogWrite(ENA, vitesse);
  analogWrite(ENB, vitesse);
  motorsStopped = false;
  ledsDroite();
}

void stopMotors() {
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, LOW);
  digitalWrite(IN3, LOW);
  digitalWrite(IN4, LOW);
  analogWrite(ENA, 0);
  analogWrite(ENB, 0);
  motorsStopped = true;
  ledsStop();
}

// ======== Fonctions LEDs ========
void toggleLEDs() {
  ledsOn = !ledsOn;
  digitalWrite(LED_GAUCHE, ledsOn);
  digitalWrite(LED_DROITE, ledsOn);
}

void ledsAvancer() {
  digitalWrite(LED_GAUCHE, LOW);
  digitalWrite(LED_DROITE, LOW);
}

void ledsReculer() {
  digitalWrite(LED_GAUCHE, HIGH);
  digitalWrite(LED_DROITE, HIGH);
}

void ledsGauche() {
  digitalWrite(LED_GAUCHE, HIGH);
  digitalWrite(LED_DROITE, LOW);
}

void ledsDroite() {
  digitalWrite(LED_GAUCHE, LOW);
  digitalWrite(LED_DROITE, HIGH);
}

void ledsStop() {
  digitalWrite(LED_GAUCHE, LOW);
  digitalWrite(LED_DROITE, LOW);
}

// ======== Buzzer non bloquant ========
void buzzerAlert() {
  static unsigned long lastTone = 0;
  static byte state = 0;
  
  if (millis() - lastTone > 200) {
    switch(state) {
      case 0:
        tone(BUZZER_PIN, 1000, 200);
        state++;
        break;
      case 1:
        tone(BUZZER_PIN, 1500, 200);
        state++;
        break;
      default:
        noTone(BUZZER_PIN);
        state = 0;
        return;
    }
    lastTone = millis();
  }
}

void handleCamera() {
  // Implémentation future
  Serial.println("Commande caméra reçue");
  webSocket.broadcastTXT("{\"status\":\"camera_not_implemented\"}");
}

// ======== Séquence de démarrage ========
void sequenceDemarrage() {
  for (int i = 0; i < 3; i++) {
    digitalWrite(LED_GAUCHE, HIGH);
    digitalWrite(LED_DROITE, LOW);
    delay(150);
    digitalWrite(LED_GAUCHE, LOW);
    digitalWrite(LED_DROITE, HIGH);
    delay(150);
  }
  digitalWrite(LED_DROITE, LOW);
  
  // Buzzer sans mouvement des moteurs
  tone(BUZZER_PIN, 1000, 200);
  delay(250);
  tone(BUZZER_PIN, 1500, 200);
  delay(250);
  noTone(BUZZER_PIN);
}