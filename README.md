# MOVING 
we are currently moving keeper.sofialondonmoskva.com to a new home, the macosx client buffers any data that is not successfully sent and it will try to send it until it succeeds, so please be patient

expected downtime: 1-2 hours

## abstract
keeper is an app that keeps track of which keeps track of which application is active. Every 300 seconds it sends the data to a server (by default https://keeper.sofialondonmoskva.com - it is defined in keepers/input/macos/keeper/AppDelegate.h). It is really helpful to know how you use your time but we couldn't trust the commercial productivity meters sooo.. here it is :) simple productivity meter in less then 600 lines of code

### how does it work
When you start the client application it checks for configured UID if it does not have one it gets brand new (128 chars) from /generate/uid/ and stores it.
Every 2 seconds the app gets current active window, if it is safari/chrome it gets URL hostname from the current tab, and stores it in a local dictionary. Every 300 seconds the data is send to a server using SSL connection. There is no information which can link `IP<->UID` in the database the only place where you can link those are in the web server's access log.

### install - client

* MacOSX (>=1.6): download from [keeper-binary-macos-10.6.zip](https://github.com/sofialondonmoskva/keeper/raw/master/input/macos/keeper/keeper-binary-macos-10.6.zip) and just start it, or open input/macos/keeper/keeper.xcodeproj and compile it, click on the status icon (that looks like a K inside a clock) and select `Productivity report` and enjoy.

### report page

the report page looks like this:
![screen shot](https://raw.github.com/sofialondonmoskva/keeper/master/screen.png "screen shot")

if you set productivity to -3 it will ignore the application and will appear at the ignor list (bottom right corner)

#### install - backend (or use the default one which runs on https://keeper.sofialondonmoskva.com)

The backend is simple `sinatra` application that uses `active_record`
```
$ git clone https://github.com/sofialondonmoskva.com/keeper
$ ruby app.rb db:migrate up # this will create simple config.rb with simple ActiveRecord::Base.establish_connection(:adapter => 'sqlite3',:database => "db.sqlite3"))
$ thin start -s 3 --socket /tmp/thin.sock -e production 
```

simple nginx config (nginx rox!):

```
upstream backend {
	server	unix:/tmp/thin.0.sock;
	server	unix:/tmp/thin.1.sock;
	server	unix:/tmp/thin.2.sock;
}

server {
    listen 443 ssl;
    access_log off;
    error_log off;
    keepalive_timeout 0;
    server_name keeper.sofialondonmoskva.com;
    root /keeper/backend/public/;

	location / {
		proxy_pass http://backend;
	}
}
```
Do not forget to recompile the `keeper client` to use your URL instead https://keeper.sofialondonmoskva.com

### keeper.sofialondonmoskva.com
There is no `access_log` and `error_log` and we can not link `UID<->IP`, of course as you know 'there is no place for truth on the internet', that is why we have published the backend code and you can run your own keeper-server and own your data. Since we do not have unlimited resources there is a simple throttle mechanism that allows 1000 POST requests per IP per day per instance (defined in backend/app.rb MAX_REQUESTS_PER_DAY).

### license
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
