GitHub Star Statistics
======================

# Description

**NB: Incomplete and work in progress as I get the time.**

See graphs, tables of repositories that have been starred.
Uses Ruby on Rails and the GitHub API.

* Repositories a user has starred per month/year
 * http://localhost:3000/
* Stars received on repositories a user owns (sources) per month/year
 * http://localhost:3000/stats/repos?user=xevix

# Requirements

* Redis (used for caching results)

# Instructions

`bin/rails server`

Visit http://localhost:3000/.
