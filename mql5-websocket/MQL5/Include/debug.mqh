#property copyright     "Copyright © 2021 Artem Maltsev (Vivazzi)"
#property link          "https://vivazzi.pro"
#property version       "1.00"
#property description   "mql_debug is additional instrument for code debugging"
#property strict

#include <Trade/AccountInfo.mqh>

#define df(debug_obj, A) debug_obj.debug_to_file(A, __FILE__ ": " __FUNCSIG__ ", line " + (string)__LINE__ + ":\n    " + #A)
#define d(debug_obj, A) df(debug_obj, A)
#define dp(debug_obj, A) debug_obj.debug_to_print(A, __FILE__ ": " __FUNCSIG__ ", line " + (string)__LINE__ + ":\n    " + #A)
#define d_clear(debug_obj) debug_obj.clear()


const string ALPHABET = "1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_";
CAccountInfo  m_account;

class Debug {
public:
    string log_path;

    int h_file;

    void _remove_wrappers(string wrapper, string &_res) {
        while(true) {
            int pos = StringFind(_res, wrapper);
            if (pos == -1) break;

            // --- find left part ---
            /*
                start with ".", #:
                    default_debug.debug_to_file(...
                                  ^ - pos
                                ^ - initial left_pos
            */
            int left_pos = pos - 2;
            while(true) {
                if (StringFind(ALPHABET, StringSubstr(_res, left_pos, 1)) != -1) left_pos--;
                else {
                  left_pos += 1;
                  break;
                }
            }
            // from left_pos to pos - need ro remove

            // --- find right part ---
            /*
                start with ".", #:
                    default_debug.debug_to_file(MathPow(2,1),__FILE__: ...
                                               ^
            */
            int right_pos = pos + StringLen(wrapper) + 1;  // start with "("
            int f_start_pos = right_pos, f_end_pos = -1;
            int f_open_parenthesis_count = 0, f_close_parenthesis_count = 0;
            int open_parenthesis_count = 1, close_parenthesis_count = 0;
            while(true) {
                // find function: need to find "," and f_open_parenthesis_count must be equal to f_close_parenthesis_count
                string a = StringSubstr(_res, right_pos, 1);
                if (f_end_pos == -1) {
                    if (StringSubstr(_res, right_pos, 1) == "(") f_open_parenthesis_count++;
                    else if (StringSubstr(_res, right_pos, 1) == ")") f_close_parenthesis_count++;
                    else if (StringSubstr(_res, right_pos, 1) == "," && f_open_parenthesis_count == f_close_parenthesis_count) f_end_pos = right_pos - 1;
                }

                // find parentheses of debug_to_file: open_parenthesis_count must be equal to close_parenthesis_count
                if (StringSubstr(_res, right_pos, 1) == "(") open_parenthesis_count++;
                else if (StringSubstr(_res, right_pos, 1) == ")") close_parenthesis_count++;

                if (open_parenthesis_count == close_parenthesis_count) break;

                right_pos++;
            }

            // form all parts: left_part + function + right_part
            _res = StringSubstr(_res, 0, left_pos) + StringSubstr(_res, f_start_pos, (f_end_pos + 1) - f_start_pos) + StringSubstr(_res, right_pos + 1);
        }
    }

    void _handle_value_desc(string &value_desc) {
        /*
            TestDebug.mq4: int OnInit(), line 15:
                default_debug.debug_to_file(MathPow(2,1),__FILE__: __FUNCSIG__, line +(string)__LINE__+:
                +MathPow(2,1))+default_debug.debug_to_file(MathAbs(-10)/2,__FILE__: __FUNCSIG__, line +(string)__LINE__+:
                +MathAbs(-10)/2) :: 7

            ->

            TestDebug.mq4: int OnInit(), line 15:
                MathPow(2,1)+MathAbs(-10)/2 :: 7
        */
        string parts[];
        StringSplit(value_desc, StringGetCharacter("\n", 0), parts);

        if (ArraySize(parts) > 1) {
            string _header = parts[0];

            string _res = "";
            for (int i=1, len = ArraySize(parts); i < len; i++) _res += parts[i];

            // remove useless "\n"
            StringReplace(_res, "\n", "");

            // remove all "debug_to_file" / "debug_to_print" wrappers
            _remove_wrappers("debug_to_file", _res);
            _remove_wrappers("debug_to_print", _res);

            value_desc = _header + "\n" + _res;
        }
    };

    Debug() {
        set_log_path("debug\\" + (string)AccountNumber() + "\\debug.txt");
    }

    Debug(string _log_path) {
        set_log_path(_log_path);
    }

    void set_log_path(string _log_path) {
        log_path = _log_path;
        create_log_file();
    }

    bool check_file(int _h_file, string file_path, int file_type) {
        if (_h_file < 0) {
            string mes;

            if (file_type == FILE_WRITE) mes = "%s: Error with file creation (error: %d)";
            else mes = "%s: Error with open file (error: %d)";

            Comment(StringFormat("%s: Error with open file (error: %d)", file_path, GetLastError()));

            return false;
        }

        return true;
    }

    void create_log_file() {
        h_file = FileOpen(log_path, FILE_WRITE);
        if (check_file(h_file, log_path, FILE_WRITE)) {
            FileClose(h_file);
        }
    }

    template <typename T>
    T debug_to_file(const T value, string value_desc, bool use_handle_value_desc=true) {
        if (use_handle_value_desc) _handle_value_desc(value_desc);

        h_file = FileOpen(log_path, FILE_READ|FILE_WRITE);
        if (check_file(h_file, log_path, FILE_WRITE)) {
            FileSeek(h_file, 0, SEEK_END);
            FileWrite(h_file, value_desc  + " :: " + (string)value);
            FileClose(h_file);
        }

        return value;
    }

    template <typename T>
    T debug_to_print(const T value, string value_desc, bool use_handle_value_desc=true) {
        if (use_handle_value_desc) _handle_value_desc(value_desc);

        Print(value_desc + " :: " + (string)value);
        return value;
    }

    void clear() {
        create_log_file();
    }
};

void AccountNumber()
{
    return m_account.Login()
}

Debug default_debug();
#define _df(A) df(default_debug, A)
#define _d(A) _df(A)
#define _dp(A) dp(default_debug, A)
#define _d_set_log_path(log_path) default_debug.set_log_path(log_path)
#define _d_clear() d_clear(default_debug)