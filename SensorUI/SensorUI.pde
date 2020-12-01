import controlP5.*;
import processing.serial.*;
import cc.arduino.*;

//Parameters with Graph design
final int screen_w = 640;          // screen width[dot]
final int screen_h = 480;          // screen hight[dot]
final int v_margin = 20;           // outside margin[dot]
final int g_margin = 20;   // btween margin[dot]
final int line_graph_w = 100000;      // Line graph width[dot = number of sample]
final int now_position=400;

int cut = 1;  //Read data every cut

//***********number of sensor**************
final int num_bar = 1;              // *****Number of sensor*****
final int bar_size = 70;            // Number bar width[%]
final int num_data = num_bar + 1;   // number of save data (+time)

//*********** Max data valu ***********
float max_data_val[] = {6.0f, 6.0f};//*********** Max data valu ***********
//final boolean signed_data = false;  // Has a negative value
final int num_auxline = 4;         // Auxiliary line[N]
final int vallabel_w = 60;         // Auxiliary line val width[dot]


// Draw Graph Constant variable
// Plot area width and higt
final int plotarea_w = screen_w - vallabel_w;
final int plotarea_h = (screen_h - (num_bar-1)*g_margin - 2*v_margin) / num_bar;
// write position
final int write_data_x = vallabel_w + now_position;
final int write_data_w = plotarea_w - now_position;
// Line graph left position
final int line_graph_x = vallabel_w;

// Y=0.0 auxiliary line index
final int main_axis = num_auxline;

// Y=0.0 hight(y)
final int bar_y[] = new int[num_bar];


// Serial Port
Serial myPort;

// Arduino data
int numData;
float data[] = new float[num_data];
float data_basis=10;//base value(Set by yourself)
float data_temp=0;  //temperature

// Ring buffer for graph display
int graph_write_pos;
float[][] graph_data = new float[num_data][line_graph_w];


ControlP5 cp5;
String startTime = "";
String endTime = "";
String valueMax = "";
String valueMin = "";
//String windowSize = ""+cut*now_position/5;
String windowSize = "";
String base = "";
String temperature="";
String fileName = "";


//*****************Arduino*******************
Arduino arduino;
int analogPin_0 = 0;
int analogPin_1 = 1;
float sens_res1;
float sens_res2;

//measurement interval [ms]
int mes_interval = 200;  //******
int current_time = 0;
int temp_time = 0;
char buf[];


//File
PrintWriter file; 
int buffer_bottom=0;
int file_start=0;
int file_end=0;


void setup() {
  
  size(1500, 480);
  
  for (int i = 0; i < num_bar; i++)
  {
    bar_y[i] =(i+1) * (screen_h - 2*v_margin) / num_bar + v_margin;
  }

  //Set up Arduino
  println(Arduino.list());
  // setup conecct Arduino [4800, 9600, 14400, 19200, 28800, 38400, 57600, 115200]
  arduino = new Arduino(this, Arduino.list()[0], 57600);

  temp_time = millis();

  //set framerate
  frameRate(120);


  //GUI
  PFont font = createFont("arial", 20);

  cp5 = new ControlP5(this);

  cp5.addTextfield("startTime")
    .setPosition(700, 350)
    .setSize(200, 30)
    .setFont(createFont("arial", 15))
    .setAutoClear(false)
    ;

  cp5.addTextfield("endTime")
    .setPosition(960, 350)
    .setSize(200, 30)
    .setFont(createFont("arial", 15))
    .setAutoClear(false)
    ;
    
  cp5.addTextfield("fileName")
    .setPosition(1220, 350)
    .setSize(200, 30)
    .setFont(createFont("arial", 15))
    .setAutoClear(false)
    ;

  cp5.addBang("reset")
    .setLabel("Time Reset")//text
    .setPosition(700, 420)
    .setSize(100, 40)
    .setFont(createFont("arial", 15))
    .getCaptionLabel().align(ControlP5.CENTER, ControlP5.CENTER)
    ;    
    
  cp5.addBang("save")
    .setLabel("File save")//text
    .setPosition(1320, 420)
    .setSize(100, 40)
    .setFont(createFont("arial", 15))
    //slider.addSlider(name, value (float), x, y, width, height)
    //.setColorActive(C1) //color when push (C1=int,color)
    //.setColorBackground(C1) //nornal color (C1=int,color)
    //.setColorForeground(recolor) //color when hover
    .setColorCaptionLabel(color(255,255,255)) //text color
    .getCaptionLabel().align(ControlP5.CENTER, ControlP5.CENTER);

  cp5.addTextfield("valueMax")
    .setPosition(700, 250)
    .setSize(200, 30)
    .setFont(createFont("arial", 15))
    .setAutoClear(false)
    ;

  cp5.addTextfield("windowSize")
    .setPosition(960, 250)
    .setSize(200, 30)
    .setFont(createFont("arial", 15))
    .setAutoClear(true)
    ;

  cp5.addTextfield("base")
    .setPosition(700, 150)
    .setSize(200, 30)
    .setFont(createFont("arial", 15))
    .setAutoClear(false)
    ;     

  cp5.addTextfield("temperature")
    .setPosition(960, 150)
    .setSize(200, 30)
    .setFont(createFont("arial", 15))
    .setAutoClear(false)
    ;     

  textFont(font);
}

// update countor(Reset every 1 second)
int update_counter;
// Number of data updates in the last 1 second
int update_rate;
// Real-time clock at the last reset[millisecond]
int update_timer0;
// Animation counter for program activity indicator
int update_anim;


// Data update frequency display
void showUpdateRate(boolean update)
{
  // count up data update
  if (update)
  {
    update_counter++;
  }

  // Update display every 0.2 second
  current_time = millis();
  if (mes_interval <= (current_time - update_timer0))
  {
    update_rate = update_counter;
    update_counter = 0;
    update_timer0 = current_time;
  }

  // Display update frequency
  textSize(14);
  textAlign(RIGHT, TOP);
  fill(192);
  String str = "Update/Sec:" +  update_rate;
  text(str, screen_w-20, 0);
  // Display program activity indicator animation
  String[] anim = { "-", "\\", "|", "/" };
  text(anim[update_anim/8], screen_w-4, 0);
  update_anim = (update_anim < 4*8-1)? update_anim+1: 0;
}

// Receive data from Arduino
boolean readFromSerial()
{
  // put your main code here, to run repeatedly:
  boolean updateData = false;

  //numData = 0;
  current_time = millis();

  if (current_time >= temp_time + mes_interval) {
    temp_time = current_time;

  /***********************************************************/
    sens_res1 = arduino.analogRead(analogPin_0);
    sens_res1 = 5.0*(sens_res1/1023.0);            //conversion 0-1023 -> 0-5[V]
    
    data[0] = current_time; 
    data[1] = sens_res1;
    //data[2] = sens_res2;
    println(data[0]);  

    numData = num_data;
    updateData = true;
  /***********************************************************/    
  } 
  return updateData;
}

// Show extension lines and labels
void drawauxline()
{
  textSize(14);
  textAlign(RIGHT, CENTER);

  for (int i = 0; i < num_bar; i++){
    for (int y = 0; y <= num_auxline; y++)
    {
      // Calculate y-coordinate of extension line
      int yy = bar_y[i] - plotarea_h + (y * plotarea_h / num_auxline);
    
      // Determine the color of the auxiliary line (Y = 0.0 is light, others are dark gray)
      int c = (y == main_axis)? 192: 64;
      stroke(c);
      fill(c);
    
      // Draw an auxiliary line
      line(vallabel_w, yy, screen_w, yy);
      // Draw an rabel
      float val = max_data_val[i] - (y * max_data_val[i] / num_auxline);
      text(nf(val, 1, 1), vallabel_w - 2, yy);
    }
    
    // Draw auxiliary lines at 60data intervals in the line graph
    stroke(32);
    for (int t = 0; t <= now_position; t += 60)
    {
      int x = line_graph_x + now_position - t;
      line(x, bar_y[i], x, bar_y[i]-plotarea_h);
    }
  }
}


// graph color (6 colors except black and white)
final int graph_color[][] = { 
  { 0, 0, 255 }, { 0, 255, 0 }, { 0, 255, 255 }, { 255, 0, 0 }, { 255, 0, 255 }, { 255, 255, 0 }
};


void draw() {
  //clear window
  background(0);

  fill(255);
  //  text(startTime, 1040,110);
  //  text(endTime, 1040,180);
  textSize(20);  // フォントの表示サイズ
//  text(valueMax, 720, 400);
//  text(valueMin, 930, 400);
  text(windowSize, 1340, 300);


  boolean updateData = readFromSerial();  // Receive data from Arduino

  // Store in ring buffer
  if (updateData){
    for (int i = 0; i < numData; i++) {
      graph_data[i][graph_write_pos] = data[i];
    }
    
    if(graph_write_pos < line_graph_w-1){
      graph_write_pos =  graph_write_pos+1;
    }else{
      graph_write_pos = 0;
      buffer_bottom = 1;
    }
  }
  
  /***********************************************************/      
  textSize(24);
  text("Time:\n"+graph_data[0][(graph_write_pos+line_graph_w-1)%line_graph_w]/1000+"sec", 800, 50);
  text("sensor:\n"+graph_data[1][(graph_write_pos+line_graph_w-1)%line_graph_w], 1050, 50);
  //text("sensor:\n"+graph_data[2][(graph_write_pos+line_graph_w-1)%line_graph_w], 1000, 50);
  //text("sensor:\n"+graph_data[5][(graph_write_pos+line_graph_w-1)%line_graph_w], 1100, 30);
  //text("sensor:\n"+graph_data[6][(graph_write_pos+line_graph_w-1)%line_graph_w], 1200, 50);
  text("Window size:\n"+cut*now_position/5+"sec", 1300, 50);
  /***********************************************************/    

  // Show extension lines and labels
  drawauxline();

  // Data update frequency display
  showUpdateRate(updateData);

  // draw graph
  textSize(14);
  textAlign(CENTER, TOP);
  for (int i = 1; i < numData; i++){
    
    int k = (graph_write_pos > 0)? graph_write_pos-1: line_graph_w-1;
    
    // label positon
    int x = write_data_x; 
    int y = bar_y[i-1] + int(-plotarea_h * graph_data[i][k] / max_data_val[i-1]);

    // color
    int c = i % 6;
    fill(graph_color[c][0], graph_color[c][1], graph_color[c][2]);
    noStroke();

    // print label
    text(nf(data[i], 1, 3), x, y);

    // draw graph
    stroke(graph_color[c][0], graph_color[c][1], graph_color[c][2]);

    for (int j = now_position; j > 0; j--)
    {
      k = (k >= cut)? k - cut: line_graph_w + k - cut;
      int yy = bar_y[i-1] + int(-plotarea_h * graph_data[i][k] / max_data_val[i-1]);
      line(line_graph_x+j, y, line_graph_x+j-1, yy);
      y = yy;
    }
  }
}

public void reset() {
  cp5.get(Textfield.class, "startTime").clear();
  cp5.get(Textfield.class, "endTime").clear();
}

public void save(){
  
  int k = (graph_write_pos > 0)? graph_write_pos-1: line_graph_w-1;
  
  if(endTime == ""){
    file_end = (graph_write_pos > 0)? graph_write_pos-1: line_graph_w-1;
  } else {
    file_end = int(endTime)*1000;
    while(graph_data[0][k] > file_end){
      k = (k >= 0)? k-1: line_graph_w-1;
    }
    file_end = k;
  }
  
  if(startTime == ""){
    file_start = buffer_bottom;
  } else {
    file_start = int(startTime)*1000;
    while(graph_data[0][k] >= file_start){
      k = (k >= 0)? k-1: line_graph_w-1;
    }
    k = (k >= 0)? k-1: line_graph_w-1;
    file_start = k;
  }
  

  if(temperature != ""){
    data_temp=float(temperature);
  }
  
  
  if(fileName==""){
    file = createWriter("SensorData/"+createFileName());
  } else {
    println(fileName + ".csv");
    file = createWriter("SensorData/"+fileName + ".csv");
  }
  file.println(data_basis);
  file.println(data_temp);
  for(int i = file_start ; i!=file_end ; i=(i+1)%graph_write_pos){
    //println(i);
    /***********************************************************/    
    file.print(graph_data[0][i]/1000.0);
    file.print(",");
    file.println(graph_data[1][i]);
    /***********************************************************/    
  }
  file.close();
  println("file saved");
}

void controlEvent(ControlEvent theEvent) {
  if (theEvent.isAssignableFrom(Textfield.class)) {
    println("controlEvent: accessing a string from controller '"
      +theEvent.getName()+"': "
      +theEvent.getStringValue()
      );

    if(theEvent.getName()=="windowSize"){
      int hoge = int(windowSize);
      cut=hoge*5/now_position;
    }
    else if(theEvent.getName()=="valueMax"){
      max_data_val[0] = float(valueMax);
      max_data_val[0] = max_data_val[0];
    }
    else if(theEvent.getName()=="base"){
      data_basis=float(base);
      println(data_basis);
    }
  }
}

public void input(String theText) {
  // automatically receives results from controller input
  println("a textfield event for controller 'input' : "+theText);
}

String createFileName() {
  String fileName= "Auto/"+nf(year(), 2) + nf(month(), 2) + nf(day(), 2) +"-"+ nf(hour(), 2) + nf(minute(), 2) + nf(second(), 2);
  fileName += ".csv";
  return fileName;
}
