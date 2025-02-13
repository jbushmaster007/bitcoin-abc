# Copyright (c) 2018 The Bitcoin developers

project(bitcoin-qt)

# This ensure that AUTOMOC doesn't run on generated files.
cmake_policy(SET CMP0071 OLD)

include(BrewHelper)
find_brew_prefix(QT5_PREFIX qt5)

set(QT_REQUIRED_COMPONENTS Core Widgets Network Test)
find_package(Qt5 COMPONENTS ${QT_REQUIRED_COMPONENTS} REQUIRED HINTS "${QT5_PREFIX}")

# Localisation
add_subdirectory(locale)

add_custom_command(OUTPUT temp_bitcoin_locale.qrc
	COMMAND cmake
	ARGS
		-E copy
		"${CMAKE_CURRENT_SOURCE_DIR}/bitcoin_locale.qrc"
		temp_bitcoin_locale.qrc
	MAIN_DEPENDENCY bitcoin_locale.qrc
	VERBATIM
)

add_custom_command(OUTPUT qrc_bitcoin_locale.cpp
	COMMAND Qt5::rcc
	ARGS
		temp_bitcoin_locale.qrc
		-name bitcoin_locale
		-o qrc_bitcoin_locale.cpp
	MAIN_DEPENDENCY temp_bitcoin_locale.qrc
	DEPENDS locales
	VERBATIM
)

# UI elements
# qt5_wrap_ui() generates the files in the CMAKE_CURRENT_BINARY_DIR. As there
# is no option to change the output directory, moving the files to the forms
# subdirectory requires to override the variable. It is reset to its actual
# value after the call so it does not impact the other sections of this
# CMakeLists.txt file.
set(SAVE_CMAKE_CURRENT_BINARY_DIR ${CMAKE_CURRENT_BINARY_DIR})
set(CMAKE_CURRENT_BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}/forms")
qt5_wrap_ui(UI_GENERATED_HEADERS
	forms/addressbookpage.ui
	forms/askpassphrasedialog.ui
	forms/coincontroldialog.ui
	forms/editaddressdialog.ui
	forms/helpmessagedialog.ui
	forms/intro.ui
	forms/modaloverlay.ui
	forms/openuridialog.ui
	forms/optionsdialog.ui
	forms/overviewpage.ui
	forms/receivecoinsdialog.ui
	forms/receiverequestdialog.ui
	forms/debugwindow.ui
	forms/sendcoinsdialog.ui
	forms/sendcoinsentry.ui
	forms/signverifymessagedialog.ui
	forms/transactiondescdialog.ui
)
set(CMAKE_CURRENT_BINARY_DIR ${SAVE_CMAKE_CURRENT_BINARY_DIR})

# Qt MOC
set(CMAKE_AUTOMOC ON)

# Handle qrc resources
qt5_add_resources(QRC_BITCOIN_CPP bitcoin.qrc)

# Do protobuf codegen
find_package(Protobuf REQUIRED)
protobuf_generate_cpp(PROTOBUF_SOURCES PROTOBUF_HEADERS paymentrequest.proto)

add_library(bitcoin-qt-base
	bantablemodel.cpp
	bitcoinaddressvalidator.cpp
	bitcoinamountfield.cpp
	bitcoingui.cpp
	bitcoinunits.cpp
	clientmodel.cpp
	csvmodelwriter.cpp
	guiutil.cpp
	intro.cpp
	modaloverlay.cpp
	networkstyle.cpp
	notificator.cpp
	optionsdialog.cpp
	optionsmodel.cpp
	peertablemodel.cpp
	platformstyle.cpp
	qvalidatedlineedit.cpp
	qvaluecombobox.cpp
	rpcconsole.cpp
	splashscreen.cpp
	trafficgraphwidget.cpp
	utilitydialog.cpp

	# Handle ui files
	${UI_GENERATED_HEADERS}

	# Protobuf codegen
	${PROTOBUF_HEADERS}
	${PROTOBUF_SOURCES}

	# Translations
	${BITCOIN_QM_FILES}

	# Handle qrc files
	${QRC_BITCOIN_CPP}
	qrc_bitcoin_locale.cpp
)

target_include_directories(bitcoin-qt-base PUBLIC ${Protobuf_INCLUDE_DIRS})

# Add the minimal integration plugin, and other plugins according to the target
# platform.
set(QT_PLUGIN_COMPONENTS QMinimalIntegrationPlugin)
set(QT_PLUGIN_PLATFORM_DEFINITIONS -DQT_QPA_PLATFORM_MINIMAL=1)

# Linux support
if(${CMAKE_SYSTEM_NAME} MATCHES "Linux")
	list(APPEND QT_PLUGIN_COMPONENTS QXcbIntegrationPlugin)
	list(APPEND QT_PLUGIN_PLATFORM_DEFINITIONS -DQT_QPA_PLATFORM_XCB=1)
endif()

# Windows support
if(${CMAKE_SYSTEM_NAME} MATCHES "Windows")
	list(APPEND QT_PLUGIN_COMPONENTS QWindowsIntegrationPlugin)
	list(APPEND QT_PLUGIN_PLATFORM_DEFINITIONS -DQT_QPA_PLATFORM_WINDOWS=1)

	target_sources(bitcoin-qt-base PRIVATE winshutdownmonitor.cpp)
endif()

# OSX support
if(${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
	list(APPEND QT_PLUGIN_COMPONENTS QCocoaIntegrationPlugin)
	list(APPEND QT_PLUGIN_PLATFORM_DEFINITIONS -DQT_QPA_PLATFORM_COCOA=1)

	target_sources(bitcoin-qt-base PRIVATE
		macdockiconhandler.mm
		macnotificationhandler.mm
	)

	set_property(TARGET bitcoin-qt-base PROPERTY AUTOMOC_MOC_OPTIONS "-DQ_OS_MAC")

	target_link_libraries(bitcoin-qt-base
		"-framework Foundation"
		"-framework ApplicationServices"
		"-framework AppKit"
	)
endif()

# Find out more about Qt. This is similar to
# http://code.qt.io/cgit/qt/qtwebkit.git/tree/Source/cmake/OptionsQt.cmake
get_target_property(QT_CORE_TYPE Qt5::Core TYPE)
if(QT_CORE_TYPE MATCHES STATIC)
	set(QT_STATIC_BUILD ON)
endif()

# Determine the Qt libraries directory from the QT5::Core library location
get_target_property(QT_CORE_LIB_LOCATION Qt5::Core LOCATION)
get_filename_component(QT5_LIB_DIR "${QT_CORE_LIB_LOCATION}" DIRECTORY)

set(STATIC_DEPENDENCIES_CMAKE_FILE "${CMAKE_BINARY_DIR}/QtStaticDependencies.cmake")
if(EXISTS ${STATIC_DEPENDENCIES_CMAKE_FILE})
	file(REMOVE ${STATIC_DEPENDENCIES_CMAKE_FILE})
endif()

set(CONVERT_PRL_PATH "${CONTRIB_PATH}/qt/convert-prl-libs-to-cmake.pl")
macro(CONVERT_PRL_LIBS_TO_CMAKE _qt_component)
	if(TARGET Qt5::${_qt_component})
		get_target_property(_lib_location Qt5::${_qt_component} LOCATION)
		execute_process(COMMAND ${PERL_EXECUTABLE} "${CONVERT_PRL_PATH}"
			--lib "${_lib_location}"
			--qt_lib_install_dir "${QT5_LIB_DIR}"
			--out "${STATIC_DEPENDENCIES_CMAKE_FILE}"
			--component "${_qt_component}"
			--compiler "${CMAKE_CXX_COMPILER_ID}"
		)
	endif()
endmacro()

if(QT_STATIC_BUILD)
	list(APPEND QT_REQUIRED_COMPONENTS ${QT_PLUGIN_COMPONENTS})

	foreach(qt_module ${QT_REQUIRED_COMPONENTS})
		CONVERT_PRL_LIBS_TO_CMAKE(${qt_module})
	endforeach()

	# HACK: We must explicitly add LIB path of the Qt installation
	# to correctly find qtpcre
	link_directories("${QT5_LIB_DIR}")

	# Now that we generated the dependencies, import them.
	set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${CONVERT_PRL_PATH}")
	if(NOT EXISTS ${STATIC_DEPENDENCIES_CMAKE_FILE})
		message(FATAL_ERROR "Unable to find ${STATIC_DEPENDENCIES_CMAKE_FILE}")
	endif()
	include(${STATIC_DEPENDENCIES_CMAKE_FILE})
	list(REMOVE_DUPLICATES STATIC_LIB_DEPENDENCIES)

	# According to Qt documentation (https://doc.qt.io/qt-5/plugins-howto.html):
	# "Plugins can be linked statically into your application.
	# If you build the static version of Qt, this is the only option for
	# including Qt's predefined plugins."
	# So if the Qt build is static, the plugins should also be static and we
	# need to define QT_STATICPLUGIN to tell the code to import <QTPlugin>.
	target_compile_definitions(bitcoin-qt-base PUBLIC -DQT_STATICPLUGIN=1)

	# Add the platform plugin definition if required
	# Setting this definition tells the code what is the target for Q_IMPORT_PLUGIN().
	foreach(qt_platform_definition ${QT_PLUGIN_PLATFORM_DEFINITIONS})
		target_compile_definitions(bitcoin-qt-base PUBLIC "${qt_platform_definition}")
	endforeach()

	# Link the required plugins
	foreach(qt_plugin ${QT_PLUGIN_COMPONENTS})
		target_link_libraries(bitcoin-qt-base Qt5::${qt_plugin})
	endforeach()
endif()

target_link_libraries(bitcoin-qt-base
	server
	rpcclient
	Qt5::Widgets
	Qt5::Network
	OpenSSL::SSL
	${Protobuf_LIBRARIES}
)

# Wallet
if(BUILD_BITCOIN_WALLET)
	# Automoc option.
	set(AUTOMOC_MOC_OPTIONS -DENABLE_WALLET=1)

	# Add wallet functionality to bitcoin-qt
	target_sources(bitcoin-qt-base
		PRIVATE
			addressbookpage.cpp
			addresstablemodel.cpp
			askpassphrasedialog.cpp
			coincontroldialog.cpp
			coincontroltreewidget.cpp
			editaddressdialog.cpp
			openuridialog.cpp
			overviewpage.cpp
			paymentrequestplus.cpp
			paymentserver.cpp
			receivecoinsdialog.cpp
			receiverequestdialog.cpp
			recentrequeststablemodel.cpp
			sendcoinsdialog.cpp
			sendcoinsentry.cpp
			signverifymessagedialog.cpp
			transactiondesc.cpp
			transactiondescdialog.cpp
			transactionfilterproxy.cpp
			transactionrecord.cpp
			transactiontablemodel.cpp
			transactionview.cpp
			walletframe.cpp
			walletmodel.cpp
			walletmodeltransaction.cpp
			walletview.cpp
	)

	target_link_libraries(bitcoin-qt-base wallet)

	if(ENABLE_QRCODE)
		target_include_directories(bitcoin-qt-base PUBLIC ${QRENCODE_INCLUDE_DIR})
		target_link_libraries(bitcoin-qt-base ${QRENCODE_LIBRARY})
	endif()
endif()

# The executable
add_executable(bitcoin-qt WIN32 bitcoin.cpp)
target_link_libraries(bitcoin-qt bitcoin-qt-base)

# Test tests
add_subdirectory(test)
