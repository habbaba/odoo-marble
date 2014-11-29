#!/usr/bin/env python
from __future__ import print_function
import erppeek
import sys, os
import psycopg2 

# constants -------------------------------------------------

CONFIG_FILE = 'db-00'
SERVER = 'localhost'
USER_DB = 'openerp'
PSW_DB = 'opener'

SIZE = [50,20,5,30,30,6,6,6,6]
FIELDS = ['model','level','id','xml_id','group','read','write','create','unlink']

# functions -------------------------------------------------

def _check_argum():
    model_filter = False
    group_filter = False
    model = ''
    group = ''

    pos_m = 0; pos_g = 0
    size_arg = len(sys.argv)
    k = 1
    pos_m = size_arg > k and str(sys.argv[k]) == '-m' and k
    pos_g = size_arg > k and str(sys.argv[k]) == '-g' and k
    k = 3 
    pos_m = pos_m or (size_arg > k and str(sys.argv[k]) == '-m' and k)
    pos_g = pos_g or (size_arg > k and str(sys.argv[k]) == '-g' and k)

    mg = ['-m','-g']
    if pos_m:
        model = size_arg > pos_m+1 and str(sys.argv[pos_m+1])
        model = model not in mg and model
        model_filter = model and pos_m and True
    if pos_g:
        group = size_arg > pos_g+1 and str(sys.argv[pos_g+1])
        group = group not in mg and group
        group_filter = group and pos_g and True

    if not (model or group):
        print("""
        oe-access.sh [-m <model>] [-g <group-xml-id>]
        > -m <model>: filter by model, p/ex: -m product.marble.dimension
        > -g <group-xml-id>: filter by group, 'module.xml_id' p/ex: -g product_marble.group_marble_adminis

        > ex: oe-access.sh -g product_marble.group_marble_adminis  
        > ex: oe-access.sh -m product.marble.dimension
        > ex: oe-access.sh -g product_marble.group_marble_adminis -m product.marble.dimension
        """)
        sys.exit(0)

    model = model if model else ''
    group = group if group else ''

    # xxx = 'mod-f = %s, mod = %s, gru-f = %s, gru = %s'
    # print(xxx % (model_filter, model, group_filter, group))
    return model, group 

def _exists_model(model_name):
    proxy = client.model('ir.model')
    ids = proxy.search([('model', '=', model_name)])
    return (len(ids) > 0)

def _get_level(lgroups, gid):
    for e in lgroups:
        if e[0] == gid:
            return e[1]
    return ''

# - - - - - - - - - - -  - - - -

def _get_sql(group_ids, model):
    group_ids = str(group_ids).lstrip('[').rstrip(']')

    groups_filter = " AND g.id IN (%s) " % group_ids if group_ids else ''
    models_filter = " AND m.model = '%s' " % model if model else ''

    sql = '''
        SELECT
            d.name, g.id, g.name, m.model, a.perm_read,
            a.perm_write, a.perm_create, a.perm_unlink
        FROM
            ir_model_access a
            JOIN ir_model m ON (a.model_id=m.id)
            JOIN res_groups g ON (a.group_id=g.id)
            LEFT JOIN ir_model_data d ON (d.model = 'res.groups' AND d.res_id=g.id)
        WHERE
              a.active IS True
         %s 
         %s 
        ORDER BY m.model, g.name;
        ''' % (groups_filter, models_filter) 

    #print('4- sql = %s' % sql)
    return sql

def _process_model_groups(mod, lgroups):
    #print('20- model = %s' % mod)
    #print('21- lgroups = %s' % lgroups)
    
    if not lgroups:
        return []

    res = []
    many_groups = lgroups and len(lgroups) > 1
    none_model = not model
    #print('22- many_groups = %s' % many_groups)

    # lgroups = [[(id,level),(id,level),..]]
    for lgro in lgroups:

        # lgro = [(id,level),(id,level),..]
        group_ids = [g[0] for g in lgro]

        # FIELDS = ['model','level','id','xml_id','group','read','write','create','unlink']
        cur.execute(_get_sql(group_ids, mod))
        val = [{FIELDS[0]:c[3],
                FIELDS[1]:_get_level(lgro, c[1]),
                FIELDS[2]:c[1],
                FIELDS[3]:c[0],
                FIELDS[4]:c[2],
                FIELDS[5]:c[4],
                FIELDS[6]:c[5],
                FIELDS[7]:c[6],
                FIELDS[8]:c[7]
            } for c in cur]

        #print('23- val = %s' % val)

        # val > [{'col1':'val1',..},{'col1':'val1',..},..]
        if many_groups or none_model:
            # muchos modelos con muchos grupos 
            # >> reduzco a summary el estado del grupo (val[0])
            val = [_get_summary(val)]
        else:
            val.append(_get_summary(val))

        #print('24- val = %s' % val)
        res.append((mod,val))

    # res > [(model,[{'col1':'val1',..},{'col1':'val1',..},..]),..]
    #print('25- res = %s' % res)
    return res

def _get_models(group):
    # recupero los models...
    lmodels = []
    cur.execute(_get_sql(group.id, ''))
    for c in cur:
        if c[3] not in lmodels:
            lmodels.append(c[3])
    return lmodels 

def _get_groups(model):
    # recupero los groups...
    lgroups = []
    cur.execute(_get_sql([], model))
    for c in cur:
        #if c[3] not in lmodels:
        lgroups.append(c[1])
    
    # devuelvo los groups como objeto
    lgroups = client.model('res.groups').browse(lgroups)
    return lgroups 

# - - - - - - - - - - -  - - - -

def _get_summary(data):
    #print('100- data = %s' % data)
    gro = _get_object(client, group_xml_id) if group_xml_id else None
    access = {'r':False, 'w':False, 'c':False, 'u':False}

    # data > [{'col1':'val1',..},{'col1':'val1',..},..]
    summ_gro = None
    for d in data:
        access['r'] = access['r'] or d[FIELDS[5]]
        access['w'] = access['w'] or d[FIELDS[6]]
        access['c'] = access['c'] or d[FIELDS[7]]
        access['u'] = access['u'] or d[FIELDS[8]]
        summ_gro = gro and gro.id == d[FIELDS[2]] and d

    #FIELDS = ['model','level','id','xml_id','group','read','write','create','unlink']
    #print('101- access = %s' % access)
    summary = {}
    if summ_gro:
        summary = {k:v for k, v in summ_gro.iteritems()}
    elif data:
        default_gro = data[0]
        summary = {
            FIELDS[0]: model if model else default_gro[FIELDS[0]],
            FIELDS[1]: gro.id if gro else default_gro[FIELDS[1]],
            FIELDS[2]: gro.id if gro else default_gro[FIELDS[2]],
            FIELDS[3]: group_xml_id.split('.')[-1] if group_xml_id else default_gro[FIELDS[3]],
            FIELDS[4]: gro.name if gro else default_gro[FIELDS[4]],
            FIELDS[5]: False, 
            FIELDS[6]: False, 
            FIELDS[7]: False, 
            FIELDS[8]: False
        }
    else:
        # not data
        summary = {
            FIELDS[0]: model if model else '',
            FIELDS[1]: gro.id if gro else '',
            FIELDS[2]: gro.id if gro else '',
            FIELDS[3]: group_xml_id.split('.')[-1] if group_xml_id else '',
            FIELDS[4]: gro.name if gro else '',
            FIELDS[5]: False, 
            FIELDS[6]: False, 
            FIELDS[7]: False, 
            FIELDS[8]: False
        }

    summary[FIELDS[5]] = str(access['r']).upper()
    summary[FIELDS[6]] = str(access['w']).upper()
    summary[FIELDS[7]] = str(access['c']).upper()
    summary[FIELDS[8]] = str(access['u']).upper()
    #print('102- summary = %s' % summary)

    # summary > {'col1':'val1',..}
    return summary

def _get_parent(level, group):
    res = []
    new_level = (level+('>' if level else '')+'%s') % group.id

    res.append((group.id,new_level))
    for g in group.implied_ids:
        res += _get_parent(new_level, g)

    return res

def _get_models_groups(model, group_xml_id):
    #print('80- group_xml_id = %s' % group_xml_id)

    # --- process models ---
    group = _get_object(client, group_xml_id) if group_xml_id else None
    #print('81- group = %s' % group)

    lmodels = [model] if model else _get_models(group)
    #print('82- lmodels = %s' % lmodels)

    # check if exisist model
    for mod in lmodels:
        if not _exists_model(mod):
            print('Do not exist model \'' + mod + '\'')
            _close_db()
            sys.exit(1)
   
    res = []
    for mod in lmodels:
        #print('83- mod = %s' % mod)

        # defino grupo (dado x usuario) o 
        # grupos (recupero los grupos vinculadois al model actual)
        lgroups = [group] if group else _get_groups(mod)
        #print('84- lgroups = %s' % lgroups)

        # por cada grupo recupero sus padres (ascendentes) 
        # > [g1, g2, g3, ..] > [[{},{},{}], [{},{}], ..]
        lgro = [_get_parent('',g) for g in lgroups]
        #print('85- lgro = %s' % lgro)
        
        # lo vinculo al modelo actual: [(model, [groups])]
        res.append((mod, lgro))            
        #print('86- res = %s' % res)
   
    #print('87- res = %s' % res)
    return res

def _get_object(client, xml_id):
    """Return the record referenced by this xml_id."""
    module, name = xml_id.split('.')
    search_domain = [('module', '=', module), ('name', '=', name)]
    data = client.model('ir.model.data').read(search_domain, 'model res_id')
    if data:
        assert len(data) == 1
        return client.model(data[0]['model']).get(data[0]['res_id'])
    return False

# --- print ----

def _print(ldata):
    # FIELDS = ['model','level','id','xml_id','group','read','write','create','unlink']
    fields = [(FIELDS[k],SIZE[k]) for k in range(len(FIELDS))]

    head = [f[0]+(' '*(f[1]-len(f[0]))) for f in fields]
    sep_head = [('-' * f[1]) for f in fields]
    sep_summary = [('.' * f[1]) for f in fields]

    head = ' '.join(head)
    sep_head = ' '.join(sep_head)
    sep_summary = ' '.join(sep_summary)

    # - - - - - -
    to_print = ['']
    to_print.append(head)
    to_print.append(sep_head)

    fsintax = [('{%s:%s}' % f) for f in fields]
    fsintax = ' '.join(fsintax)

    # - - - - - -
    #print('7- field-sintax = %s' % fsintax)
    #print('8- ldata = %s' % ldata)
    
    one_model = len(ldata) == 1
    none_model = not model

    # ldata >> [(model,[{'col1':'val1',..},{'col1':'val1',..},..]),..]
    for mod, data in ldata:
        #print('9- d = %s' % str(d))
        #curr_model = d[0]
        #curr_data  = d[1]

        # data >> [(model,[{'col1':'val1',..},{'col1':'val1',..},..]),..]
        for d in data:
            if one_model and d == data[-1]:
                to_print.append(sep_summary)

            line = [str(d[f[0]]) + (' ' * (f[1] - len(str(d[f[0]])))) for f in fields]
            to_print.append(' '.join(line))

            if one_model and d == data[-1]:
                #to_print.append(sep_summary)
                to_print.append('')

    for p in to_print:
        print(p)
    
# --- db ---
def _open_db():
    server, db, user, psw = erppeek.read_config(CONFIG_FILE)
    conn = psycopg2.connect(dbname=db, user=USER_DB, password=PSW_DB, host=SERVER)
    cur = conn.cursor()
    return conn, cur

def _close_db():
    cur.close()
    conn.close()

# main -------------------------------------------------------

if __name__ != "__main__":
    sys.exit(1)

# ----------------------------------------
path = str(sys.argv[0]).split('/')
file = path[len(path)-1].strip()
path = '/'.join(path[:len(path)-1]).strip() 
current_path = os.getcwd()

os.chdir(path)
client = erppeek.Client.from_config(CONFIG_FILE)
os.chdir(path)

# ----------------------------------------

# check arguments
model, group_xml_id = _check_argum()
#print('main-1- model = %s, group = %s' % (model, group_xml_id))

# 
conn, cur = _open_db()

# get models + groups > [(model,[groups]), ..] > [(model, [{}, {}, ..])]
lmodels = _get_models_groups(model, group_xml_id)
#print('main-2- lmodels = %s' % lmodels)

# recupero los datos (por model y grupos) y proceso > [(model,[group]),..]
# >> [(model,[{'col1':'val1',..},{'col1':'val1',..},..]),..]
ldata = []
for mod, lgroups in lmodels:
    ldata += _process_model_groups(mod, lgroups)

#print('main-3- ldata = %s' % ldata)

_close_db()
#print('main-3- ldata = %s' % ldata)

# imprimo...
_print(ldata)

sys.exit(0)


