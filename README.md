# ProcessingTrackingVisualiser

A front end to an ArUco tracking system built in Processing

## Key Information
- The tracking system operates on the Wifi network SSID "SwarmTracker"
- The tracking system server will always have the IP address 192.168.8.2
- For robots, they need to connect a TCP/IP client to 192.168.8.2 port 5000
- For data logging from your computer, you should connect a TCP/IP client to 192.168.8.2 port 8000
- ArUco markers are used for tracking.
	- Robots will always be assigned an IP address in the range 192.168.8.[3-50]
	- You can print markers with ID above 200 to define and track other details
	- You can generate markers to print at this <a href="https://chev.me/arucogen/">webpage</a>.
	- Markers should be configured as 4x4, and 45mm in size.
- You will receive example code for the M5Stack Core2 that
	- connects to the WiFi
	- receives an ID number (based on IP address)
	- draws an ArUco marker to the display
	- establishes a TCP/IP client
	- collected pose information (e.g., x, y, theta)
	- sends some example data back to the tracking system
	

## Connecting to the Tracking System

To connect to the tracking system, you will need to configure you computer to connect to the Wifi network SwarmTracker or SwarmTracker5G with the password provided to you.  Connecting to the tracking system will allow you to store tracking information data to your computer.

## Connecting Robots

Each robot must also connect to the same Wifi network (SwarmTracker).  A robot should connect a TCP/IP client to the tracking system using the IP address 192.168.8.2 and port 5000.  Some example code to achieve with the M5Stack Core2 will be provided to you.  

The robot should be programmed to receive a data struct like:

```c
typedef struct {
  uint8_t marker_id;
  float x;
  float y;
  float theta;
  uint32_t sequence;
  uint8_t quality;
} pose_packet_t;
```

This data is sent from the tracking system server every 100ms (10hz, 10 updates per second).    


A robot can send information back to the tracking system server, for example, any results you wish to log (this could be data variables within your robot controler).  The robot can transmit a string up to 1024 bytes long.  This can be achieved with code like the following:

```c

char buf[1024];
memset( buf, 0, sizeof( buf ));
sprintf(buf, "Time is %lu\n", millis() );
client.write( buf, strlen( buf ) );

```

The tracking system server will report robot positions by prefixing a P, and any messages from robots (i.e. your results) by prefixing with M.  For more information, see the next section.


## Accessing Tracking System Server Data, Storing Results

To access the data from the tracking system, you can connect to the server on 192.168.8.2 port 8000.  If you are using a linux distribution, this can be done quickly using the netcat command, such as:

>> nc 192.168.8.2 8000

This will then print the tracking system data to your command line.  To save this data, you can extend the command with:

>> nc 192.168.8.2 8000 > results.csv

If you are not using a linux distribution, you may find using <a href="https://putty.org/index.html">PuTTY</a> more convenient.  You should configure Putty with the address 192.168.8.2, port 8000, and type "raw".  


The tracking system will report pose data of detected markers, and any messages sent to the tracking system by the robots.  When reporting, pose information is prefixed with a P, and messages with an M.  Some example output is below:

>> P,34,0.2880, -0.5425, 1.6101, 323,90,02:37:45.954 
>> P,207,0.5023, -0.6217, -2.4650, 0,111,02:37:45.985 
>> P,207,0.5023, -0.6217, -2.4650, 0,111,02:37:46.018 
>> P,207,0.5023, -0.6217, -2.4650, 0,111,02:37:46.048 
>> M,34,hello, time is 180371,02:37:46.055 
>> P,34,0.2880, -0.5425, 1.6101, 324,90,02:37:46.055 

For pose (P), the comma separated values are MessageType, ID, x, y, theta, sequence_number, quality, time_of_day.
For message (M), the output is MessageType, ID, [ your string ], time_of_day.

### Accessing the Tracking System via Processing.org

An example Processing sketch is provided in this repository that will visualise the markers being tracked, and save all data to a .csv file.  This visualiser is intended to help you set up the system - it may help you to understand the coordinate system and it's relationship to the space available.



