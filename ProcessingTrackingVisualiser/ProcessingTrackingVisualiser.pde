import processing.net.*;
import java.util.HashMap;
import java.util.ArrayList;
import java.util.Collections;

PrintWriter csv_output;
boolean     csv_open;

// -----------------------------------------------------------------------------
// Connection settings
// -----------------------------------------------------------------------------
String SERVER_IP = "192.168.8.2";
int SERVER_PORT = 8000;

Client trackingClient;
String receiveBuffer = "";

int reconnectIntervalMs = 2000;
int lastConnectAttemptMs = -reconnectIntervalMs;
boolean connectionWasActive = false;

// -----------------------------------------------------------------------------
// World/display settings
// Adjust these to match the physical tracking area, in metres.
// -----------------------------------------------------------------------------
float WORLD_MIN_X = -1.0;
float WORLD_MAX_X =  1.0;
float WORLD_MIN_Y = -1.0;
float WORLD_MAX_Y =  1.0;
float GRID_SPACING = 0.25;

int STALE_AFTER_MS = 1000;
int MAX_RECEIVE_BUFFER = 65536;
int MAX_LOG_MESSAGES = 8;

HashMap<Integer, RobotPose> robots = new HashMap<Integer, RobotPose>();
ArrayList<String> messageLog = new ArrayList<String>();

long receivedLineCount = 0;
long malformedLineCount = 0;

void setup() {
  size(1200, 800);
  surface.setTitle("Robot Tracking System");
  frameRate(60);

  csv_open = false;
  try {
    csv_output = createWriter("./results.csv");
    csv_open = true;
  }
  catch( Exception e ) {
    println(" Couldn't create new csv file, error: " + e );
    csv_open = false;
  }


  textFont(createFont("SansSerif", 14));
  connectToServer();
}

void draw() {
  background(238);

  updateNetwork();
  drawTitleBar();
  drawWorldPanel(20, 72, 790, 625);
  drawInformationPanel(830, 72, 300, 625);
}

// -----------------------------------------------------------------------------
// TCP client
// -----------------------------------------------------------------------------
void connectToServer() {
  lastConnectAttemptMs = millis();


  println("Attempting to connect to server...");
  if (trackingClient != null) {
    trackingClient.stop();
    trackingClient = null;
  }

  try {
    trackingClient = new Client(this, SERVER_IP, SERVER_PORT);

    if (trackingClient.active()) {
      connectionWasActive = true;
      addLog("Connected to " + SERVER_IP + ":" + SERVER_PORT);
    }
  }
  catch (Exception e) {
    trackingClient = null;
    connectionWasActive = false;
  }

  println(" ok");
}

void updateNetwork() {
  boolean connected = trackingClient != null && trackingClient.active();

  if (!connected) {
    if (connectionWasActive) {
      addLog("Connection lost");
      connectionWasActive = false;
    }

    if (millis() - lastConnectAttemptMs >= reconnectIntervalMs) {
      connectToServer();
    }
    return;
  }

  connectionWasActive = true;

  // readString() returns all bytes currently waiting in the TCP receive buffer.
  // They are accumulated here because a TCP read may contain a partial line,
  // one complete line, or several complete lines.
  while (trackingClient.available() > 0) {
    String incoming = trackingClient.readString();

    if (incoming == null || incoming.length() == 0) {
      break;
    }

    receiveBuffer += incoming;

    if (receiveBuffer.length() > MAX_RECEIVE_BUFFER) {
      receiveBuffer = "";
      malformedLineCount++;
      addLog("Receive buffer cleared: no newline found");
      return;
    }
  }

  extractCompleteLines();
}

void extractCompleteLines() {
  int newlinePosition = receiveBuffer.indexOf('\n');

  while (newlinePosition >= 0) {
    String line = receiveBuffer.substring(0, newlinePosition).trim();
    receiveBuffer = receiveBuffer.substring(newlinePosition + 1);

    if (line.length() > 0) {
      receivedLineCount++;
      parseIncomingLine(line);
    }

    newlinePosition = receiveBuffer.indexOf('\n');
  }
}

// -----------------------------------------------------------------------------
// Message parsing
// -----------------------------------------------------------------------------
void parseIncomingLine(String line) {
  try {
    char messageType = line.charAt(0);

    if (messageType == 'P') {
      parsePoseMessage(line);
      if ( csv_open ) csv_output.println( line );
    } else if (messageType == 'M') {

      parseTextMessage(line);
      if ( csv_open ) csv_output.println( line );
    } else {
      addLog("Unknown message: " + line);
    }
  }
  catch (Exception e) {
    malformedLineCount++;
    addLog("Could not parse: " + shorten(line, 42));
  }
}

void parsePoseMessage(String line) {
  // P,id,x,y,theta,sequence_number,quality,time
  String[] field = split(line, ',');

  if (field.length != 8) {
    throw new RuntimeException("Pose message requires 8 fields");
  }

  int id = Integer.parseInt(field[1].trim());
  float x = Float.parseFloat(field[2].trim());
  float y = Float.parseFloat(field[3].trim());
  float theta = Float.parseFloat(field[4].trim());
  int sequenceNumber = Integer.parseInt(field[5].trim());
  int quality = Integer.parseInt(field[6].trim());
  String sourceTime = field[7].trim();

  RobotPose robot = robots.get(id);

  if (robot == null) {
    robot = new RobotPose(id, robotColour(id));
    robots.put(id, robot);
  }

  robot.update(x, y, theta, sequenceNumber, quality, sourceTime);
}

void parseTextMessage(String line) {
  // M,id,message text,time
  // The message text is allowed to contain commas, so locate the first two
  // commas and the final comma rather than using split().
  int firstComma = line.indexOf(',');
  int secondComma = line.indexOf(',', firstComma + 1);
  int finalComma = line.lastIndexOf(',');

  if (firstComma < 0 || secondComma < 0 || finalComma <= secondComma) {
    throw new RuntimeException("Invalid text message");
  }

  int id = Integer.parseInt(line.substring(firstComma + 1, secondComma).trim());
  String message = line.substring(secondComma + 1, finalComma).trim();
  String sourceTime = line.substring(finalComma + 1).trim();

  addLog(sourceTime + "  Robot " + id + ": " + message);
}

// -----------------------------------------------------------------------------
// Drawing
// -----------------------------------------------------------------------------
void drawTitleBar() {
  fill(30);
  textAlign(LEFT, CENTER);
  textSize(24);
  text("Robot Tracking System", 20, 34);

  boolean connected = trackingClient != null && trackingClient.active();
  int indicatorColour = connected ? color(55, 175, 90) : color(205, 65, 65);

  fill(indicatorColour);
  noStroke();
  ellipse(width - 205, 34, 13, 13);

  fill(45);
  textSize(14);
  text(connected ? "TCP connected" : "TCP disconnected", width - 188, 34);
}

void drawWorldPanel(float panelX, float panelY, float panelW, float panelH) {
  drawPanel(panelX, panelY, panelW, panelH);

  float margin = 42;
  float mapX = panelX + margin;
  float mapY = panelY + margin;
  float mapW = panelW - margin * 2;
  float mapH = panelH - margin * 2;

  fill(252);
  stroke(120);
  strokeWeight(1);
  rect(mapX, mapY, mapW, mapH);

  drawWorldGrid(mapX, mapY, mapW, mapH);

  for (RobotPose robot : robots.values()) {
    drawRobot(robot, mapX, mapY, mapW, mapH);
  }

  fill(60);
  textSize(13);
  textAlign(CENTER, TOP);
  text("x position (m)", mapX + mapW / 2, mapY + mapH + 16);

  pushMatrix();
  translate(mapX - 29, mapY + mapH / 2);
  rotate(-HALF_PI);
  text("y position (m)", 0, 0);
  popMatrix();
}

void drawWorldGrid(float x, float y, float w, float h) {
  textSize(10);

  float firstX = ceil(WORLD_MIN_X / GRID_SPACING) * GRID_SPACING;
  for (float gx = firstX; gx <= WORLD_MAX_X + 0.0001; gx += GRID_SPACING) {
    float screenX = worldToScreenX(gx, x, w);

    if (abs(gx) < 0.0001) {
      stroke(90);
      strokeWeight(2);
    } else {
      stroke(215);
      strokeWeight(1);
    }

    line(screenX, y, screenX, y + h);
    fill(90);
    textAlign(CENTER, TOP);
    text(nf(gx, 0, 2), screenX, y + h + 3);
  }

  float firstY = ceil(WORLD_MIN_Y / GRID_SPACING) * GRID_SPACING;
  for (float gy = firstY; gy <= WORLD_MAX_Y + 0.0001; gy += GRID_SPACING) {
    float screenY = worldToScreenY(gy, y, h);

    if (abs(gy) < 0.0001) {
      stroke(90);
      strokeWeight(2);
    } else {
      stroke(215);
      strokeWeight(1);
    }

    line(x, screenY, x + w, screenY);
    fill(90);
    textAlign(RIGHT, CENTER);
    text(nf(gy, 0, 2), x - 5, screenY);
  }
}

void drawRobot(RobotPose robot, float mapX, float mapY, float mapW, float mapH) {
  float screenX = worldToScreenX(robot.x, mapX, mapW);
  float screenY = worldToScreenY(robot.y, mapY, mapH);

  int ageMs = millis() - robot.localUpdateTimeMs;
  int alphaValue = ageMs <= STALE_AFTER_MS ? 255 : 90;

  pushMatrix();
  translate(screenX, screenY);

  // World y is drawn upwards, while Processing screen y increases downwards.
  // Negating theta preserves the usual mathematical counter-clockwise heading.
  rotate(-robot.theta);

  stroke(30, alphaValue);
  strokeWeight(2);
  robot.qualityToDisplayColor();
  fill(robot.displayColour);//, alphaValue);
  ellipse(0, 0, 25, 25);

  if ( robot.id < 200 ) {
    strokeWeight(3);
    line(0, 0, 22, 0);
    line(22, 0, 14, -6);
    line(22, 0, 14, 6);
  }
  
  popMatrix();
  fill(25, alphaValue);
  textAlign(LEFT, BOTTOM);
  textSize(13);
  text("ID " + robot.id, screenX + 16, screenY - 3);

  textSize(10);
  textAlign(LEFT, TOP);
  text("Q=" + robot.quality + " \nS=" + robot.sequenceNumber, screenX + 16, screenY + 2);
}

void drawInformationPanel(float x, float y, float w, float h) {
  drawPanel(x, y, w, h);

  float cursorY = y + 22;

  fill(35);
  textAlign(LEFT, TOP);
  textSize(17);
  text("Connection", x + 18, cursorY);
  cursorY += 30;

  textSize(13);
  fill(70);
  text("Server", x + 18, cursorY);
  fill(25);
  text(SERVER_IP + ":" + SERVER_PORT, x + 100, cursorY);
  cursorY += 21;

  fill(70);
  text("Lines", x + 18, cursorY);
  fill(25);
  text(Long.toString(receivedLineCount), x + 100, cursorY);
  cursorY += 21;

  fill(70);
  text("Malformed", x + 18, cursorY);
  fill(25);
  text(Long.toString(malformedLineCount), x + 100, cursorY);
  cursorY += 21;

  fill(70);
  text("Robots", x + 18, cursorY);
  fill(25);
  text(str(robots.size()), x + 100, cursorY);
  cursorY += 38;

  fill(35);
  textSize(17);
  text("Latest poses", x + 18, cursorY);
  cursorY += 29;

  drawPoseTable(x + 18, cursorY, w - 36);
  cursorY += 202;

  fill(35);
  textSize(17);
  text("Messages", x + 18, cursorY);
  cursorY += 28;

  textSize(11);
  fill(55);
  for (int i = 0; i < messageLog.size(); i++) {
    text(messageLog.get(i), x + 18, cursorY, w - 36, 38);
    cursorY += 42;
  }

  fill(95);
  textSize(11);
  textAlign(LEFT, BOTTOM);
  text("R: reconnect     C: clear messages", x + 18, y + h - 14);
}

void drawPoseTable(float x, float y, float w) {
  fill(225);
  noStroke();
  rect(x, y, w, 22);

  fill(45);
  textSize(11);
  textAlign(LEFT, CENTER);
  text("ID", x + 4, y + 11);
  text("x", x + 28, y + 11);
  text("y", x + 75, y + 11);
  text("theta", x + 122, y + 11);
  text("Q", x + 174, y + 11);
  text("time", x + 220, y + 11);

  ArrayList<Integer> ids = new ArrayList<Integer>(robots.keySet());
  Collections.sort(ids);

  int maximumRows = 8;
  int rowCount = min(maximumRows, ids.size());

  for (int row = 0; row < rowCount; row++) {
    RobotPose robot = robots.get(ids.get(row));
    float rowY = y + 22 + row * 22;

    if (row % 2 == 1) {
      fill(246);
      noStroke();
      rect(x, rowY, w, 22);
    }

    int ageMs = millis() - robot.localUpdateTimeMs;
    fill(ageMs <= STALE_AFTER_MS ? 35 : 145);
    textAlign(LEFT, CENTER);
    textSize(9);

    text(str(robot.id), x + 4, rowY + 11);
    text(nf(robot.x, 1, 3), x + 28, rowY + 11);
    text(nf(robot.y, 1, 3), x + 75, rowY + 11);
    text(nf(robot.theta, 1, 3), x + 122, rowY + 11);
    text(nf(robot.quality,0,0)+"%", x + 174, rowY + 11);
    text(robot.sourceTime, x + 210, rowY + 11);
  }
}

void drawPanel(float x, float y, float w, float h) {
  fill(255);
  stroke(205);
  strokeWeight(1);
  rect(x, y, w, h, 8);
}

// -----------------------------------------------------------------------------
// Utilities
// -----------------------------------------------------------------------------
float worldToScreenX(float worldX, float mapX, float mapW) {
  return map(worldX, WORLD_MIN_X, WORLD_MAX_X, mapX, mapX + mapW);
}

float worldToScreenY(float worldY, float mapY, float mapH) {
  return map(worldY, WORLD_MIN_Y, WORLD_MAX_Y, mapY + mapH, mapY);
}

int robotColour(int id) {
  int redValue = 70 + abs(id * 53) % 150;
  int greenValue = 70 + abs(id * 97) % 150;
  int blueValue = 70 + abs(id * 139) % 150;
  return color(redValue, greenValue, blueValue);
}

void addLog(String message) {
  messageLog.add(0, shorten(message, 78));

  while (messageLog.size() > MAX_LOG_MESSAGES) {
    messageLog.remove(messageLog.size() - 1);
  }

  println(message);
}

String shorten(String value, int maximumLength) {
  if (value.length() <= maximumLength) {
    return value;
  }

  return value.substring(0, maximumLength - 3) + "...";
}

void keyPressed() {
  if (key == 'r' || key == 'R') {
    addLog("Manual reconnect requested");
    connectToServer();
  }

  if (key == 'c' || key == 'C') {
    messageLog.clear();
  }
}

void exit() {
  if (trackingClient != null) {
    trackingClient.stop();
  }
  if ( csv_open ) {
    csv_output.flush();
    csv_output.close();
    println(" Closed csv file ");
  }

  super.exit();
}

// -----------------------------------------------------------------------------
// Data model
// -----------------------------------------------------------------------------
class RobotPose {
  int id;
  float x;
  float y;
  float theta;
  int sequenceNumber;
  float quality;
  String sourceTime = "";
  int localUpdateTimeMs = 0;
  int displayColour;

  RobotPose(int id, int displayColour) {
    this.id = id;
    this.displayColour = displayColour;
  }

  void qualityToDisplayColor() {
     color c0 = color( 220,  0, 0);
     color c1 = color(   0,220, 0);
     this.displayColour = lerpColor( c0, c1, this.quality/100.0);
  }

  void update(float x, float y, float theta, int sequenceNumber, int quality, String sourceTime) {
    this.x = x;
    this.y = y;
    this.theta = theta;
    this.sequenceNumber = sequenceNumber;
    this.quality = quality;
    this.sourceTime = sourceTime;
    this.localUpdateTimeMs = millis();
  }
}
