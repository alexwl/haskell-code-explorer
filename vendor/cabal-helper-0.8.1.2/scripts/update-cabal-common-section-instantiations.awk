BEGIN {
        delete sections;
        section="";
        ignoring=0;
}

/^[[:space:]]*$/ {
        section="";
        ignoring=0;
}

{
        if(section) {
                tmp = sections[section];
                sections[section] = tmp (tmp ? RS : "") $0;
        }
}

/^[[:space:]]*-- *Common/ {
        section = $3
}

/^[[:space:]]*-- *Instantiate *common/ {
        ignoring=1

        print $0;
        print sections[$4];
}

{
        if(!ignoring) {
                print $0;
        }
}
