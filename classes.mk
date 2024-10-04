# Some example Minion classes

# Mkdir(DIR) : Create directory
#
Mkdir.inherit = Builder
Mkdir.in =
Mkdir.out = $(_arg1)
Mkdir.mkdirs =
Mkdir.vvFile = # without {mkdirs}, this will fail
Mkdir.command = mkdir -p {@}


# Remove(FILE) : Remove FILE from the file system
#
Remove.inherit = Phony
Remove.in =
Remove.command = rm -f $(_arg1)


# Touch(FILE) : Create empty file
#
Touch.inherit = Builder
Touch.in =
Touch.out = $(_arg1)
Touch.command = touch {@}


# Tar(INPUTS) : Construct a TAR file
#
Tar.inherit = Builder
Tar.outExt = .tar
Tar.command = tar -cvf {@} {^}


# Unzip(OUT) : Extract from a zip file
#
#   The argument is the name of the file to extract from the ZIP file.  The
#   ZIP file name is based on the class name.  Declare a subclass with the
#   appropriate name, or override its `in` property to specify the zip file.
#
Unzip.inherit = Builder
Unzip.command = unzip -p {<} $(_argText) > {@} || rm {@}
Unzip.in = $(_class).zip


# Zip(INPUTS) : Construct a ZIP file
#
Zip.inherit = Builder
Zip.outExt = .zip
Zip.command = zip {@} {^}


