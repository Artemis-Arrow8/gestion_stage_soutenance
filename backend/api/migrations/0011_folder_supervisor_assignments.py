# Migration créée pour borner côté base les dossiers visibles par chaque encadreur.
# Les clés étrangères en cascade retirent les affectations devenues obsolètes.

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('api', '0010_jury_member_accounts'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='FolderSupervisor',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('folder', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='supervisor_assignments', to='api.internshipfolder')),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='folder_assignments', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'db_table': 'folder_supervisor',
                'constraints': [models.UniqueConstraint(fields=('user', 'folder'), name='unique_supervisor_folder_assignment')],
            },
        ),
    ]
