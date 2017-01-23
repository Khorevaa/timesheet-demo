# Building a simple timesheet app with SlashDB, Go and Vue

## Requirements
* [SlashDB](https://www.slashdb.com/) >= 0.9.15
* [Go](https://golang.org/dl/) >= 1.7.4
* [Vue](https://vuejs.org/v2/guide/installation.html) >= 2.1.10

## The Code
All the code refereed in this article is available at the [bitbucket GIT repository](https://bitbucket.org/slashdb/timesheet/src).

## The basic concept
Is to build a simple poof of concept time tracking app, either for local use or as a network 
available service and basing it on SlashDB.

### The timesheet app layout:
```
RESTful API <---> (small authentication/authorization proxy app <---> frontend GUI)
```
What the developer needs to implement is, the frontend GUI 
and also a way to implement authentication/authorization for the user.
The RESTful part is provided to us for free by SlashDB.

## SlashDB
For the DB back-end I will be using [SlashDB](https://www.slashdb.com/). 
It can automatically generates a REST API from relational databases making it easy to access and modify our data. 
In general, it will save a lot of work coding my own data API-s.

## Go
[Go](https://golang.org/) (Golang for search engines) is a language by Google, often used as a (micro)service building tools. 
It has most batteries included, allowing us to build a simple authentication layer between our data and the frontend. 
It's also a compiled language i.e. we can build statically linked binaries for easy distribution and even embed our assets (CSS, js etc) 
into that binary.

## Vue
After my experience with Angular 1.x (and a bit of React), 
I choose [Vue](https://vuejs.org/) - a small and simple front-end js framework. 
It's somewhere between those two frameworks (but a lot closer to React) and 
only focuses on the V(iew) part of MVC. 
On the Angular side, we have things like template directives (i.e. *ng-for="item in items"* -> *v-for="item in items"*) 
so no cumbersome JSX transpiling by default (a plus - at least for me). 
On Reacts side, one-way data flow i.e. always parent node -> child node (so harder to achieve the level of craziness like in Angular). 
In general ease of use and comprehension of what the app is doing, also the awesome [dev tools](https://github.com/vuejs/vue-devtools) :)

### SlashDB Service

> **Important**: This part requires you to understand the basic of *SQL* and DB server setup 
(if you choose to use something other thant SQLite).

For development purposes, SlashDB is [available for free use](https://www.slashdb.com/download/) 
and I recommend using the [docker](https://docs.slashdb.com/user-guide/docker.html) image for an easy way to get started.

```
$ docker pull slashdb/slashdb
$ mkdir timesheet-docker
$ cd timesheet-docker
$ wget -c http://downloads.slashdb.com/v0.9/default-slashdb-configs_0.9.15.zip
$ unzip default-slashdb-configs_0.9.15.zip
$ docker run -d -p 8000:80 -v $PWD/slashdb:/etc/slashdb -v $PWD/slashdb:/var/log/slashdb slashdb/slashdb
```

Go to [http://localhost:8000/](http://localhost:8000/) and follow the initial developer setup wizard.

Now we need to create a database, in this example I'll be using MySQL, but any [DB engine supported by SlashDB](https://www.slashdb.com/pricing/) will do. 
Installing/configuring MySQL server is outside of scope of this article, so I'll just skip this part. 
For the timesheet app we'll need a database (preferably named *timesheet*), 
a user with read/write privileges to said DB and 3 tables: *project*, *user* and *timesheet*.

```sql
DROP TABLE IF EXISTS project;
CREATE TABLE `project` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(50) NOT NULL,
  `description` varchar(150) DEFAULT NULL,
  `timestamp` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `project_id_uindex` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


DROP TABLE IF EXISTS user;
CREATE TABLE `user` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `username` varchar(35) NOT NULL,
  `email` varchar(50) DEFAULT NULL,
  `passwd` varchar(150) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `user_id_uindex` (`id`),
  UNIQUE KEY `user_username_uindex` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


DROP TABLE IF EXISTS timesheet;
CREATE TABLE `timesheet` (
  `user_id` int(11) NOT NULL,
  `project_id` int(11) NOT NULL,
  `date` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `duration` double NOT NULL,
  `accomplishments` varchar(150) DEFAULT NULL,
  PRIMARY KEY (`user_id`,`project_id`,`date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
```

This is MySQL-s SQL dialect, but it gives a general idea about the table layout 
and is easy enough to adjust for other SQL dialects.

After we have our DB, tables and user setup we need to make SlashDB aware of it.
Going to [http://localhost:8000/](http://localhost:8000/) and logging-in as the *admin*,
we can [config and add our database endpoint](https://docs.slashdb.com/user-guide/config-databases.html).
For simplicity, I named the endpoint *timesheet*.
In this case, I also enabled the *Auto Discover* feature and provided credentials for my MySQL user.
Save, remembering to make sure the DB was connected without errors (green *Connected* status) and we're set.

It's a good idea to create a new user for remote access to our resources, 
so following the [docs](https://docs.slashdb.com/user-guide/config-users.html),
I'll add a user named - you guessed it - *timesheet*. 
Also as our proxy authorization/authentication app will connect to SlashDB directly it's a good idea 
to set an API key for that user - in this example: *timesheet-api-key*.
Finally, add our newly created data source to this users *Database Mappings* and *Save*. 
Login as the *timesheet* user, and check if we have access to our tables.
Going to the [project endpoint](http://localhost:8000/db/timesheet/project.html), 
we should see an empty table - but (hopefully) no errors.

Thats it - no you have your data provided as an RESTful API, curtesy of SlashDB :)

### GoLang proxy authorization/authentication app

> **Important**: This part requires you to understand some basics of programming in Go, 
its setup (i.e. [$GOPATH/$GOROOT(https://github.com/golang/go/wiki/GOPATH)]) 
and it's basic tooling (i.e. go get/build/install). Form more reference on that visit Go-s 
[wiki page](https://github.com/golang/).

The basic idea is to proxy all the request from the frontend to the SlashDB RESTful API 
and on the fly do some resource authorization. 
Also we need to provide a way to create and authenticate *timesheet* app users.

In my setup, this proxy-like app will have 4 endpoints.
```
/          - the SlashDB proxy
/app/      - the frontend app itself
/app/reg/  - user registration provider
/app/auth/ - user login/token provider
```

In the spirit of keeping it simple, as a method of of providing a kind of stateless session, we'll use [JWT](https://jwt.io/).
The */app/auth/* endpoint will check user credentials and if everything's OK, provide a JWT token.

First, things first lets install everything we'll need:
```
$ go get golang.org/x/crypto/pbkdf2
$ go get github.com/dgrijalva/jwt-go/...
$ go get github.com/jteeuwen/go-bindata/...
$ go get github.com/elazarl/go-bindata-assetfs/...
```

> Tip: you can just run the build.sh script to install all requirements and compile the app.

#### Setting up authorization/authentication proxy

Using GoLangs builtin *httputil.ReverseProxy*, we create a lightweight reverse proxy:

```go
// for the full code, view auth.go source file
func setupProxy() {
	// get address for the SlashDB instance and parse the URL
	url, err := url.Parse(pa.SdbInstanceAddr)
	if err != nil {
		log.Fatalln(err)
	}

	// create a reverse proxy
	proxy := httputil.NewSingleHostReverseProxy(url)
	// make it play nice with https endpoints
	proxy.Transport = &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}

	...

	// bind the proxy handler to "/"
	http.HandleFunc("/", authorizationMiddleware(proxyHandler))
}
```

So now, when requesting something from the default *localhost:8000* 
request will get redirected to the root of the selected SlashDB instance 
i.e. requesting 
> http://localhost:8000/db/timesheet/project/project_id/1.json -> http://demo.slashdb.com/db/timesheet/project/project_id/1.json

and the response will be transparently returned to the us.

The *authorizationMiddleware* function applies all the authorization logic to the proxied requests i.e.
it extracts the JWT token and checks if it's valid and depending on the user it allows 
or prohibits resource access.

```go
func authorizationMiddleware(fn func(http.ResponseWriter, *http.Request), secret []byte) func(w http.ResponseWriter, r *http.Request) {
	return func(w http.ResponseWriter, r *http.Request) {
		token, err := request.ParseFromRequest(r, request.OAuth2Extractor, func(token *jwt.Token) (interface{}, error) {
			// we simply check the token claims but this is a good place
			// to parse the r.URL.Path or orther request paramethers
			// to determin if a given user can access requested data
			// check if user of ID = 8 can read /db/timesheet/project/project_id/2/
			mc := token.Claims.(jwt.MapClaims)
			_, ok := mc["id"]
			if !ok {
				return nil, fmt.Errorf("token lacks 'id' claim")
			}
			_, ok = mc["username"]
			if !ok {
				return nil, fmt.Errorf("token lacks 'username' claim")
			}

			if len(secret) == 0 {
				secret = defaultSecret
			}
			return secret, nil
		})

		if err != nil || !token.Valid {
			http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
			return
		}
		fn(w, r)
	}
}
```

In my example it's only a simple function, but of course we can implement 
any kind of authentication logic there, depending on the use case.

#### Implementing /app/reg/

Before we can login we need a user, and for that we need to implement a way to register one.
We need to generate a password hash and store it in the DB and SlashDB comes in handy here.

```go
...
encodedPass := genPassword(un+passwd, nil)
payload := map[string]string{
  "username": un,
  "passwd":   encodedPass,
  "email":    email,
}
data, err := json.Marshal(payload)
...

req, _ = http.NewRequest("POST", pa.SdbInstanceAddr+"/db/"+pa.SdbDBName+"/user.json?"+pa.ParsedSdbAPIKey+"="+pa.ParsedSdbAPIValue, bytes.NewReader(data))
ureq, err := defaultClient.Do(req)
...

if ureq.StatusCode != http.StatusCreated {
  // something went wrong, provide some useful response to the user or just return what SlashDB has returned
}
w.WriteHeader(http.StatusCreated)
w.Write([]byte(fmt.Sprintf("User %q was created successfully!", un)))
```

Here we simply make a *POST* request to SlashDB-s /db/timesheet/user.json providing necessary info - no SQL required.

#### Implementing /app/auth/

Before we can authenticate we ned to authorize and generate the *JWT* token.
This is done at the */app/auth/* endpoint, the *authHandler* handler function, 
user input (received via form data or URL params), and passes the necessary things to *genJWTToken*.

```go
var defaultSecret = []byte("timesheet app secret")

func genJWTToken(username string, id int, secret []byte) (string, error) {
	token := jwt.NewWithClaims(jwt.SigningMethodHS512, jwt.MapClaims{
		"username": username,
		"id":       id,
		"exp":      time.Now().Add(time.Hour * 24).Unix(),
	})
	if len(secret) == 0 {
		secret = defaultSecret
	}
	return token.SignedString(defaultSecret)
}
```

Then, if everything goes according to plan, in JSON form, we return the new token to the user.

```go
tc := struct {
  Token string `json:"accessToken"`
}{st}

td, err := json.Marshal(tc)
if err != nil {
  log.Printf("data: %v, error: %v", tc, err)
  http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
  return
}
w.Write(td)
```

On the frontend side, we set the *Authorization* header and store the 
token in *localStorage* for future use i.e.

```javascript
storeAuthInfo: function (authInfo) {
    Vue.http.headers.common['Authorization'] = 'Bearer ' + authInfo.accessToken;
    this.authInfo = authInfo;
    this.userId = authInfo.payload.id;
    this.userName = authInfo.payload.username;
    localStorage.setItem(this.lsAuthInfoKey, JSON.stringify(authInfo));
}
```