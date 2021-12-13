class ZCL_BADI_IMPL_SMQ_INFO definition
  public
  inheriting from /UI2/CL_ADE_BADI_DEFAULT
  final
  create public .

public section.

  interfaces /UI2/IF_ADE_BADI_CALLBACK_SRC .

  methods CONSTRUCTOR .

  methods /UI2/IF_ADE_BADI_DATA_PROVIDER~GET_DISPLAY_NAME
    redefinition .
  methods /UI2/IF_ADE_BADI_DATA_PROVIDER~GET_SOURCE_INFORMATION
    redefinition .
  methods /UI2/IF_ADE_BADI_DATA_PROVIDER~VERIFY_SOURCE_AVAILABLE
    redefinition .
protected section.

  data MV_MANDT type SYMANDT .
  data MV_SYSID type SYSYSID .
  data MV_TEMPLATE_LINK type STRING .
private section.
ENDCLASS.



CLASS ZCL_BADI_IMPL_SMQ_INFO IMPLEMENTATION.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Public Method ZCL_BADI_IMPL_SMQ_INFO->/UI2/IF_ADE_BADI_CALLBACK_SRC~CALLBACK_REMOTE_SOURCE
* +-------------------------------------------------------------------------------------------------+
* | [--->] P_TASK                         TYPE        CLIKE
* +--------------------------------------------------------------------------------------</SIGNATURE>
  METHOD /ui2/if_ade_badi_callback_src~callback_remote_source.
***---------------------------------------------------------------------------------------------------------
*** This method is called, when the RFC retrieves a result. With the statement RECEIVE RESULTS FROM FUNCTION
*** the actual exporting parameters are obtained from the FM. The messages should then be mapped to the
*** standard message format of /ui2/ade_s_diagnostics_log. In the last step the messages are passed to the
*** proxy instance. The proxy instance will take care of delivering them to App Support.
***---------------------------------------------------------------------------------------------------------
    DATA: lt_rfcqueue      TYPE STANDARD TABLE OF trfcqin,
          lv_message(250)  TYPE c.

    "Get messages from callback
    RECEIVE RESULTS FROM FUNCTION 'TRFC_GET_QIN_INFO_DETAILS'
     TABLES
        qtable        = lt_rfcqueue
     EXCEPTIONS
        system_failure        = 1 MESSAGE lv_message
        communication_failure = 2 MESSAGE lv_message
        OTHERS = 3.


    "map messages to target format
    LOOP AT lt_rfcqueue ASSIGNING FIELD-SYMBOL(<ls_entry>).
      "we are only interested in queues in status failed
      IF <ls_entry>-qstate <> 'SYSFAIL'.
        CONTINUE.
      ENDIF.

      "build a message line for each sysfail SMQ2 entry
      APPEND VALUE #(
             s_keys         = ms_keys
             username       = ms_keys-username
             source         = /ui2/if_ade_badi_data_provider=>sc_source_remote
             type           = 'E'
             msg_date       = <ls_entry>-qrfcdatum
             msg_time       = <ls_entry>-qrfcuzeit
             error_text     = <ls_entry>-errmess
             context        = substring( val = <ls_entry>-qname off = 14 )      "add delivery number as context information (last part of queue name)
             sysid          = mv_sysid                                          "determined in GET_SOURCE_INFORMATION
             client         = mv_mandt                                          "determined in GET_SOURCE_INFORMATION

             "The template link has been set GET_SOURCE_INFORMATION for easier use here. Read more will now lead to the SMQ2 log entry.
             more_info_link = replace( val = mv_template_link sub = 'MYPLACEHOLDER' with = <ls_entry>-qname )
      ) TO mt_messages.

    ENDLOOP.

    "set in result list in the proxy instance, which will dispatch it to the UI
    me->mo_proxy_instance->callback_remote_data_source( iv_id       = ms_keys-id
                                                        it_messages = mt_messages ).


  ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Public Method ZCL_BADI_IMPL_SMQ_INFO->/UI2/IF_ADE_BADI_DATA_PROVIDER~GET_DISPLAY_NAME
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_APP_TYPE                    TYPE        /UI2/FDM_APP_TYPE
* | [--->] IV_DEST                        TYPE        RFCDEST
* | [<---] ES_DISPLAY_NAME                TYPE        /UI2/ADE_S_DISPLAY_NAMES
* | [<---] EV_LINK_TO_LOG                 TYPE        /UI2/ADE_LINK
* | [!CX!] /IWBEP/CX_MGW_NOT_IMPL_EXC
* | [!CX!] /UI2/CX_ADE
* +--------------------------------------------------------------------------------------</SIGNATURE>
  METHOD /ui2/if_ade_badi_data_provider~get_display_name.
***---------------------------------------------------------------------------------------------------------
*** In this method App Support retrieves the name of the menu entry and a link to an original log
*** transaction, for example a general link to SLG1.
***---------------------------------------------------------------------------------------------------------

    "This is the name displayed in the menu, ideally the text is translated into different languages
    es_display_name-name = 'Deliveries Inbound Queue'.

    "this method creates a WebGUI link for the entered transaction
    ev_link_to_log = /ui2/cl_ade_configuration=>get_instance( )->create_webgui_link(
      EXPORTING
        iv_transaction = 'SMQ2'
        iv_rfc_destination = iv_dest ).


  ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Public Method ZCL_BADI_IMPL_SMQ_INFO->/UI2/IF_ADE_BADI_DATA_PROVIDER~GET_SOURCE_INFORMATION
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_RFC_DEST                    TYPE        RFCDEST
* | [--->] IS_KEYS                        TYPE        /UI2/ADE_S_KEYS
* | [<---] ET_MESSAGES                    TYPE        /UI2/ADE_T_DIAGNOSTICS_LOG
* | [!CX!] /IWBEP/CX_MGW_NOT_IMPL_EXC
* | [!CX!] /UI2/CX_ADE
* +--------------------------------------------------------------------------------------</SIGNATURE>
  METHOD /ui2/if_ade_badi_data_provider~get_source_information.
***--------------------------------------------------------------------------------------------
*** The usage of this method depends on the type of Source, which is being used. In case the
*** messages are retrieved from a local source, the source (db table, local fm, etc.) can be
*** collected here directly and passed to ET_MESSAGES.
*** For a remote source it is  recommended to use the asynchronuous processing, via usage of
*** STARTING NEW TASK. This way the application remains stable, even if the remote source
*** triggers a timeout. In case of a remote source the messages are retrieved in method
*** CALLBACK_REMOTE_SOURCE and do not have to be provided here.
***---------------------------------------------------------------------------------------------
    DATA:
      lv_task(32) TYPE c,
      lv_qname    TYPE trfcqnam,
      lv_message  TYPE c LENGTH 250.


    IF mv_mandt IS INITIAL.
      " set client and system id to add them in CALLBACK_REMOTE_SOURCE
      /ui2/cl_ade_configuration=>get_instance( )->get_system_client_by_rfc_dest(
        EXPORTING
          iv_rfc_dest = iv_rfc_dest " Logical RFC Destination - Points to SAP system
        IMPORTING
          ev_sysid    = mv_sysid    " Target system
          ev_client   = mv_mandt    "target client
      ).

      "later in the callback function we can't call this method, as we run in background -> therefore create template link for log queues
      mv_template_link = /ui2/cl_ade_configuration=>get_instance( )->create_webgui_link(
        EXPORTING
          iv_transaction = 'SMQ2'
          it_query_parms = VALUE #( ( name = 'QNAME' value = 'MYPLACEHOLDER' ) ) "this is the parameter in SMQ2 -> MYPLACEHOLDER will be removed later
          iv_rfc_destination = iv_rfc_dest ).
    ENDIF.

    "This entry depends on how the RFC queues are setup in the remote system. Here we're reading inbound queues from the same system
    "and client, as EWM is on the same system.
    lv_qname = 'DLWS' && mv_sysid && 'CLNT' && mv_mandt && '*'.

    "To call the function module in a separate task, we need to provide a task id. Ideally related to our BAdI
    lv_task = is_keys-id.

    "Here the remote RFC function module is called in a new task. As a callback the interface method callback_remote_source
    "is used, which has to be implemented by this class (Implement interface /UI2/IF_ADE_BADI_CALLBACK_SRC)
    CALL FUNCTION 'TRFC_GET_QIN_INFO_DETAILS'
         STARTING NEW TASK lv_task "maximum length 32
         DESTINATION iv_rfc_dest
         CALLING /ui2/if_ade_badi_callback_src~callback_remote_source ON END OF TASK
         EXPORTING
           qname         = lv_qname
           client        = mv_mandt
         EXCEPTIONS
           communication_failure = 1 MESSAGE lv_message
           system_failure = 2  MESSAGE lv_message
           OTHERS = 3.
    IF sy-subrc <> 0.
      /ui2/cx_ade=>raise_error_in_fm(
        EXPORTING
          iv_fm_name = 'TRFC_GET_QIN_INFO_DETAILS'
          iv_error   = CONV #( lv_message )
      ).
    ENDIF.
  ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Public Method ZCL_BADI_IMPL_SMQ_INFO->/UI2/IF_ADE_BADI_DATA_PROVIDER~VERIFY_SOURCE_AVAILABLE
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_RFC_DEST                    TYPE        RFCDEST
* | [--->] IS_KEYS                        TYPE        /UI2/ADE_S_KEYS
* | [--->] IV_ACTVTY                      TYPE        ACTIV_AUTH
* | [<---] EV_AVAILABLE                   TYPE        CHAR01
* | [<---] EV_OTHER_USER                  TYPE        ABAP_BOOL
* | [!CX!] /IWBEP/CX_MGW_NOT_IMPL_EXC
* | [!CX!] /UI2/CX_ADE
* +--------------------------------------------------------------------------------------</SIGNATURE>
  METHOD /ui2/if_ade_badi_data_provider~verify_source_available.
***---------------------------------------------------------------------------------------------------------
*** In this method App Support decides, if the BAdi implementation is relevant for the current application
*** to retrieve the correct appkey, simply debug the first time here, when in the application.
***---------------------------------------------------------------------------------------------------------
    ev_available = /ui2/if_ade_badi_data_provider~sc_status_not_available.

    "Check if App = Display Outbound delivery (Type: WebGUI, Tx: VL02n)
    IF is_keys-appkey <> 'X-SAP-UI2-PAGE:X-SAP-UI2-CATALOGPAGE:SAP_LE_BC_OD_PROC:00O2TOBXDLX6WIZLS0DUK2RL0'.
      RETURN.
    ENDIF.

    "now some more specific check, if the BAdI should be called here. In this scenario a log from a remote server
    "is retrieved. Therefore we wait for a adeRemoteServer entry. If the log is from a local source, simply wait for
    "adeLocalServer
    IF is_keys-id_lvl1 <> 'adeLocalServer'.
      "-! Important - this will make the entry available in the UI - after method GET_DISPLAY_NAME has been implemented
      ev_available = /ui2/if_ade_badi_data_provider~sc_status_available.
      "-! Important - set keys for remote proxy processing in CALLBACK_REMOTE_SOURCE and message handling
      ms_keys = is_keys.
      "-!  register at App Support proxy hub, as this BAdI implements the remote interface, additionally set is remote in CONSTRUCTOR
      me->register_at_proxy( ).
    ENDIF.
  ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Public Method ZCL_BADI_IMPL_SMQ_INFO->CONSTRUCTOR
* +-------------------------------------------------------------------------------------------------+
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method CONSTRUCTOR.
    "-! register as remote source here
    super->constructor( iv_is_remote = abap_true ).
  endmethod.
ENDCLASS.