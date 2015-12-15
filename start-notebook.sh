#!/bin/bash

exec su $NB_USER -c "jupyter notebook $*"
