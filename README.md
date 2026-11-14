# Customizations to Blacklight for UC Berkeley Museums

This repo contains a customized Blacklight application. It is basically a fork of the initial UCB museum [radiance](https://github.com/cspace-deployment/radiance) portals that were customized by John Lowe, upgraded to Blacklight 8 and Rails 7.

Blacklight is a Ruby on Rails application. Refer to the Blacklight project documention for details about how to maintain and deploy applications of this sort:  http://projectblacklight.org/

## Dependencies

* Ruby 3.3.x
* Rails 7.x
* Blacklight version 8.x

* Node v14.x or later (JS minifier gem `terser` requires a JavaScript runtime)

* Python (for running the tenant installer script)

## Local development

### Installing a museum tenant

The `portal` directory is where the application lives. Running the following script will copy shared files from `ucb_extras/common` into `portal`, then copy tenant-specific files from `ucb_extras/<TENANT>` into `portal`.

For example, to install the BAMPFA portal execute this from the `glimmer` directory:

```python ./ucb_utils/tenant_installer.py bampfa```

### Running unit tests

Unit tests are written in rspec. The unit tests for each museum tenant consist of shared specs from `ucb_extras/common` and tenant-specific specs from `ucb_extras/<TENANT>`.

* Install a museum tenant (see above)
* `bundle exec rspec`

### Compiling front-end assets

Most assets are managed using importmaps, but some legacy Javascript/CSS requires the use of Sprockets.

Assets must be compiled after installing a tenant and after making changes to CSS or JavaScript files:

* `cd portal`
* `bin/rails assets:precompile`

### Starting the Rails server

* Install a museum tenant (see above)
* Compile the assets (see above)
* `bin/rails s`

## Image server URL

Images, derivatives, PDFs and 3-D files are linked as `<IMAGESERVER_URL>/blobs/<csid>/...`. The base URL comes from the `IMAGESERVER_URL` environment variable, read once at boot (`ucb_extras/common/config/initializers/imageserver.rb`). When it's unset or empty, each museum uses the legacy imageserver, `https://webapps.cspace.berkeley.edu/<museum>/imageserver`.

On a server, set it in the museum's Apache vhost and restart the app:

```apache
SetEnv IMAGESERVER_URL "https://images.example.org/pahma/imageserver"
```

### Switching between image servers

`ucb_utils/imageserver-switch.sh` switches a deployment between the legacy imageserver and another one. The vhost holds two `SetEnv IMAGESERVER_URL` lines, the legacy one and the other one, with exactly one of them commented out. Run it as a user with sudo (not `app_cspace`), from the deployed copy of this repo:

* `ucb_utils/imageserver-switch.sh status`: show both lines and the value the running app has
* `ucb_utils/imageserver-switch.sh -n legacy`: preview a switch (shows the diff, changes nothing)
* `ucb_utils/imageserver-switch.sh legacy` or `... new`: back up the vhost, switch, run `apache2ctl configtest` (restoring the backup if it fails), then ask before reloading Apache and restarting the app. Answering no restores the backup.

The defaults are `-c /etc/apache2/sites-available/portal-qa.conf` and `-m pahma` (the app at `~app_cspace/projects/search_pahma`). Pass them for other vhosts or museums. After a switch, load a page so the app restarts, then run `status`.
