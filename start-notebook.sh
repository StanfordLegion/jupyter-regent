#!/bin/bash

#exec su $NB_USER -c "env PATH=$PATH jupyter notebook $*"
#exec su $NB_USER -c "env PATH=\"$PATH\" jupyter notebook $*"
echo exec su $NB_USER -c "jupyter notebook $*"
exec su $NB_USER -c "jupyter notebook $*"
